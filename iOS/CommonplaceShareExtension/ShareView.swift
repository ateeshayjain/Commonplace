import SwiftUI
import UniformTypeIdentifiers

/// Quick save: find the shared link, send it to process-url, show "Saved",
/// and close. No form; tags and categories are added later in the app.
struct ShareView: View {
    let extensionContext: NSExtensionContext?
    let onComplete: () -> Void
    let onCancel: () -> Void

    private enum Phase {
        case saving
        case saved
        case failed(String)
    }

    @State private var phase: Phase = .saving

    // Brand accent (the app's AccentColor asset is not bundled in the extension)
    private let accent = Color(red: 0x3F / 255, green: 0x51 / 255, blue: 0xB5 / 255)

    var body: some View {
        VStack(spacing: 16) {
            switch phase {
            case .saving:
                ProgressView()
                    .controlSize(.large)
                Text("Saving to Sangrah…")
                    .font(.headline)
            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(accent)
                Text("Saved to Sangrah")
                    .font(.headline)
                Text("The summary will be ready in a moment.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
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
        .task { await saveSharedLink() }
    }

    private func saveSharedLink() async {
        guard let url = await sharedURL() else {
            phase = .failed("No link was found in what you shared.")
            return
        }
        do {
            try await ShareExtensionService.shared.saveURL(url)
            phase = .saved
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(for: .seconds(1.2))
            onComplete()
        } catch {
            phase = .failed(error.localizedDescription)
        }
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

    func saveURL(_ url: String) async throws {
        // Same session as the app: refreshed here when the access token is near expiry
        let sessions = SessionManager.shared
        var status = try await post(url, token: accessToken(from: sessions))
        if status == 401 {
            status = try await post(url, token: accessToken(from: sessions, forceRefresh: true))
        }
        switch status {
        case 200...299: return
        case 401, 403: throw ShareError.notAuthenticated
        default: throw ShareError.saveFailed
        }
    }

    private func accessToken(from sessions: SessionManager, forceRefresh: Bool = false) async throws -> String {
        do {
            return try await sessions.validAccessToken(forceRefresh: forceRefresh)
        } catch SessionError.signedOut {
            throw ShareError.notAuthenticated
        }
    }

    private func post(_ url: String, token: String) async throws -> Int {
        var request = URLRequest(url: URL(string: Config.processURLEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["url": url, "categories": []])
        request.timeoutInterval = 20

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ShareError.saveFailed }
        return http.statusCode
    }
}

enum ShareError: LocalizedError {
    case notAuthenticated
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Open Sangrah and sign in, then share again."
        case .saveFailed:
            return "The save didn't go through. Please try again."
        }
    }
}
