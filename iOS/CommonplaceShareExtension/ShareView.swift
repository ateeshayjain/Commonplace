import SwiftUI
import UniformTypeIdentifiers
import ImageIO

/// Quick save: find the shared link (or the shared screenshots), send it to
/// process-url, show "Saved", and close. No form; tags and categories are
/// added later in the app.
struct ShareView: View {
    let extensionContext: NSExtensionContext?
    let onComplete: () -> Void
    let onCancel: () -> Void

    private enum Phase {
        case saving(String)
        case saved(String)
        case failed(String)
    }

    @State private var phase: Phase = .saving("Saving to Sangrah…")

    // Brand accent (the app's AccentColor asset is not bundled in the extension)
    private let accent = Color(red: 0x3F / 255, green: 0x51 / 255, blue: 0xB5 / 255)

    var body: some View {
        VStack(spacing: 16) {
            switch phase {
            case .saving(let message):
                ProgressView()
                    .controlSize(.large)
                Text(message)
                    .font(.headline)
            case .saved(let detail):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(accent)
                Text("Saved to Sangrah")
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.orange)
                Text("Couldn't save")
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button("Done", action: onCancel)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .padding(.top, 4)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .task { await saveShared() }
    }

    /// A link wins when there is one (Safari can attach a preview image too);
    /// otherwise shared images are saved together as one screenshot save
    private func saveShared() async {
        do {
            if let url = await sharedURL() {
                try await ShareExtensionService.shared.saveURL(url)
                finish(PlanTierCache.isPro ? "The summary will be ready in a moment." : "It'll be in your Library in a moment.")
                return
            }
            let images = sharedImages()
            guard !images.isEmpty else {
                phase = .failed("No link or image was found in what you shared.")
                return
            }
            if PlanTierCache.isPro, try await uploadForClaude(images) {
                return
            }
            try await readOnDevice(images)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Pro: uploads the screenshots for Claude to read and summarise. False
    /// when the server says the account isn't Pro after all (a stale plan).
    private func uploadForClaude(_ images: [NSItemProvider]) async throws -> Bool {
        let total = images.count
        phase = .saving(total == 1 ? "Saving screenshot…" : "Saving \(total) screenshots…")
        do {
            try await ShareExtensionService.shared.saveScreenshots(images) { uploaded in
                phase = .saving("Uploading \(uploaded + 1) of \(total)…")
            }
        } catch ShareError.refused(let code, _) where code == "pro_required" {
            PlanTierCache.store(isPro: false)
            return false
        }
        finish("Sangrah is reading \(total == 1 ? "it" : "them in order"). The article will be ready in a minute.")
        return true
    }

    /// Free: reads the screenshots on this iPhone and saves the text
    private func readOnDevice(_ images: [NSItemProvider]) async throws {
        let total = images.count
        phase = .saving(total == 1 ? "Reading screenshot…" : "Reading \(total) screenshots…")
        let article = await ScreenshotReader.article(from: images) { index in
            if total > 1 { phase = .saving("Reading \(index + 1) of \(total)…") }
        }
        guard !article.body.isEmpty else { throw ShareError.noTextFound }
        phase = .saving("Saving…")
        try await ShareExtensionService.shared.saveScreenshotText(article)
        finish("Saved as one article in your Library.")
    }

    private func finish(_ detail: String) {
        phase = .saved(detail)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            onComplete()
        }
    }

    /// Image attachments in the order they were shared (the order picked in Photos)
    private func sharedImages() -> [NSItemProvider] {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return [] }
        return items
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
            .prefix(ShareExtensionService.maxScreenshots)
            .map { $0 }
    }

    /// The first URL among the shared items: a URL attachment, or plain text
    /// that is itself a URL (how X and some other apps share links).
    private func sharedURL() async -> String? {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return nil }
        for item in items {
            for attachment in item.attachments ?? [] {
                if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try? await attachment.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
                   url.scheme?.hasPrefix("http") == true {
                    return url.absoluteString
                }
            }
            for attachment in item.attachments ?? [] {
                if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = try? await attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
                   let url = firstURL(in: text) {
                    return url
                }
            }
        }
        return nil
    }

    private func firstURL(in text: String) -> String? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.firstMatch(in: text, range: range)?.url?.absoluteString
    }
}

// MARK: - Share Extension Service

final class ShareExtensionService {
    static let shared = ShareExtensionService()

    /// Matches SCREENSHOT_MAX_COUNT in process-url and the activation rule in Info.plist
    static let maxScreenshots = 10
    /// Long edge after resizing: plenty for reading text, a few hundred KB each
    private static let screenshotMaxPixels = 1800

    func saveURL(_ url: String) async throws {
        try await send(["url": url, "categories": []])
    }

    /// Screenshots read on the device (free accounts): the joined text only
    func saveScreenshotText(_ article: ScreenshotText.Article) async throws {
        try await send(["screenshotText": article.body, "title": article.title, "categories": []])
    }

    /// Posts to process-url as the signed-in user, refreshing the token once on a 401
    private func send(_ body: [String: Any]) async throws {
        // Same session as the app: refreshed here when the access token is near expiry
        let sessions = SessionManager.shared
        var reply = try await post(body, token: accessToken(from: sessions))
        if reply.status == 401 {
            reply = try await post(body, token: accessToken(from: sessions, forceRefresh: true))
        }
        try Self.check(reply)
    }

    /// Throws for anything but success; a refusal (the day's free saves used
    /// up, a Pro-only feature) carries the server's own words
    private static func check(_ reply: (status: Int, data: Data)) throws {
        switch reply.status {
        case 200...299: return
        case 401, 403: throw ShareError.notAuthenticated
        default:
            struct Refusal: Decodable { let error: String; let code: String }
            if let refusal = try? JSONDecoder().decode(Refusal.self, from: reply.data) {
                throw ShareError.refused(code: refusal.code, message: refusal.error)
            }
            throw ShareError.saveFailed
        }
    }

    /// Uploads the images to screenshots/{user}/{batch}/{n}.jpg, then asks
    /// process-url to read them, in order, into one saved article
    @MainActor
    func saveScreenshots(_ providers: [NSItemProvider], progress: @escaping (Int) -> Void) async throws {
        let sessions = SessionManager.shared
        var token = try await accessToken(from: sessions)
        guard let userId = Self.userId(fromAccessToken: token) else { throw ShareError.notAuthenticated }

        let batch = UUID().uuidString.lowercased()
        var paths: [String] = []
        for (index, provider) in providers.enumerated() {
            progress(index)
            guard let jpeg = await Self.resizedJPEG(from: provider) else { continue }
            let path = "\(userId)/\(batch)/\(index + 1).jpg"
            var status = try await upload(jpeg, to: path, token: token)
            if status == 401 {
                token = try await accessToken(from: sessions, forceRefresh: true)
                status = try await upload(jpeg, to: path, token: token)
            }
            guard (200...299).contains(status) else {
                throw status == 401 || status == 403 ? ShareError.notAuthenticated : ShareError.saveFailed
            }
            paths.append(path)
        }
        guard !paths.isEmpty else { throw ShareError.unreadableImages }

        let body: [String: Any] = ["screenshots": paths, "categories": []]
        var reply = try await post(body, token: token)
        if reply.status == 401 {
            reply = try await post(body, token: try await accessToken(from: sessions, forceRefresh: true))
        }
        try Self.check(reply)
    }

    private func upload(_ jpeg: Data, to path: String, token: String) async throws -> Int {
        var request = URLRequest(url: URL(string: "\(Config.supabaseURL)/storage/v1/object/screenshots/\(path)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let (_, response) = try await URLSession.shared.upload(for: request, from: jpeg)
        guard let http = response as? HTTPURLResponse else { throw ShareError.saveFailed }
        return http.statusCode
    }

    /// The signed-in user's id: the `sub` claim of the access token (a JWT).
    /// Only used to name the upload folder; the server checks it against the token.
    static func userId(fromAccessToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = claims["sub"] as? String else { return nil }
        return sub.lowercased()
    }

    /// A JPEG no larger than screenshotMaxPixels on its long edge
    static func resizedJPEG(from provider: NSItemProvider) async -> Data? {
        guard let cgImage = await downscaledImage(from: provider, maxPixels: screenshotMaxPixels) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.75)
    }

    /// The image no larger than maxPixels on its long edge. ImageIO reads a
    /// downscaled copy straight from the file, so a full-size image is never decoded
    /// (share extensions get little memory).
    static func downscaledImage(from provider: NSItemProvider, maxPixels: Int) async -> CGImage? {
        guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) else { return nil }

        let source: CGImageSource?
        switch item {
        case let url as URL: source = CGImageSourceCreateWithURL(url as CFURL, nil)
        case let data as Data: source = CGImageSourceCreateWithData(data as CFData, nil)
        case let image as UIImage:
            guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
            source = CGImageSourceCreateWithData(data as CFData, nil)
        default: source = nil
        }
        guard let source else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private func accessToken(from sessions: SessionManager, forceRefresh: Bool = false) async throws -> String {
        do {
            return try await sessions.validAccessToken(forceRefresh: forceRefresh)
        } catch SessionError.signedOut {
            throw ShareError.notAuthenticated
        }
    }

    private func post(_ body: [String: Any], token: String) async throws -> (status: Int, data: Data) {
        var request = URLRequest(url: URL(string: Config.processURLEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ShareError.saveFailed }
        return (http.statusCode, data)
    }
}

enum ShareError: LocalizedError {
    case notAuthenticated
    case saveFailed
    case unreadableImages
    case noTextFound
    /// The server turned the save down: the day's free saves are used up, or a Pro-only feature
    case refused(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Open Sangrah and sign in, then share again."
        case .saveFailed:
            return "The save didn't go through. Please try again."
        case .unreadableImages:
            return "Those images couldn't be opened. Try sharing them again from Photos."
        case .noTextFound:
            return "No text was found in those screenshots."
        case .refused(_, let message):
            return message
        }
    }
}
