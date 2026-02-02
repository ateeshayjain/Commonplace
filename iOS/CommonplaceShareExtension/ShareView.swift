import SwiftUI
import UniformTypeIdentifiers

struct ShareView: View {
    let extensionContext: NSExtensionContext?
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var url: String = ""
    @State private var title: String = ""
    @State private var selectedCategories: Set<String> = []
    @State private var isLoading = false
    @State private var isSaved = false
    @State private var error: String?

    private let categories = [
        ("Technology", "💻"),
        ("Business", "📊"),
        ("Health", "🏥"),
        ("Science", "🔬"),
        ("Culture", "🎭"),
        ("Design", "🎨")
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if isSaved {
                    savedConfirmation
                } else {
                    saveForm
                }
            }
            .navigationTitle("Save to Commonplace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
        .task {
            await extractSharedContent()
        }
    }

    private var saveForm: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Preview
                VStack(alignment: .leading, spacing: 8) {
                    if !title.isEmpty {
                        Text(title)
                            .font(.headline)
                            .lineLimit(2)
                    }

                    Text(url)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                // Categories
                VStack(alignment: .leading, spacing: 8) {
                    Text("Categories (optional)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                        ForEach(categories, id: \.0) { category in
                            CategoryChipView(
                                name: category.0,
                                icon: category.1,
                                isSelected: selectedCategories.contains(category.0),
                                action: {
                                    if selectedCategories.contains(category.0) {
                                        selectedCategories.remove(category.0)
                                    } else {
                                        selectedCategories.insert(category.0)
                                    }
                                }
                            )
                        }
                    }
                }

                Spacer(minLength: 20)

                // Error
                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                // Actions
                VStack(spacing: 12) {
                    Button(action: save) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Save")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .disabled(isLoading || url.isEmpty)
                }
            }
            .padding()
        }
    }

    private var savedConfirmation: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("Saved!")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Processing in background.\nWe'll notify you when it's ready.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button("Done") {
                onComplete()
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .padding()
    }

    private func extractSharedContent() async {
        guard let extensionContext = extensionContext,
              let item = extensionContext.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else {
            return
        }

        for attachment in attachments {
            // Try URL first
            if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                do {
                    if let sharedURL = try await attachment.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                        self.url = sharedURL.absoluteString
                    }
                } catch {
                    print("Failed to load URL: \(error)")
                }
            }

            // Try plain text
            if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                do {
                    if let text = try await attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                        if let sharedURL = URL(string: text), sharedURL.scheme != nil {
                            self.url = text
                        } else {
                            self.title = String(text.prefix(100))
                        }
                    }
                } catch {
                    print("Failed to load text: \(error)")
                }
            }
        }

        // Try to get title
        if let attributedTitle = item.attributedTitle?.string {
            self.title = attributedTitle
        } else if let contentText = item.attributedContentText?.string, title.isEmpty {
            self.title = String(contentText.prefix(100))
        }
    }

    private func save() {
        isLoading = true
        error = nil

        Task {
            do {
                try await ShareExtensionService.shared.saveURL(
                    url,
                    categories: Array(selectedCategories)
                )

                await MainActor.run {
                    isSaved = true
                    // Haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }

                // Auto-dismiss after delay
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                onComplete()

            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Category Chip

struct CategoryChipView: View {
    let name: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(icon)
                    .font(.system(size: 12))
                Text(name)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color(.systemGray6))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
    }
}

// MARK: - Share Extension Service

class ShareExtensionService {
    static let shared = ShareExtensionService()

    // These would come from a shared config
    private let supabaseURL = "YOUR_SUPABASE_URL"
    private let supabaseKey = "YOUR_SUPABASE_ANON_KEY"

    func saveURL(_ url: String, categories: [String]) async throws {
        // Get auth token from shared keychain
        guard let token = getSharedAuthToken() else {
            throw ShareError.notAuthenticated
        }

        var request = URLRequest(url: URL(string: "\(supabaseURL)/functions/v1/process-url")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")

        let body: [String: Any] = [
            "url": url,
            "categories": categories
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ShareError.saveFailed
        }
    }

    private func getSharedAuthToken() -> String? {
        // For demo mode, return a demo token
        // In production, this would read from shared keychain

        // Read from shared keychain (App Group)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "supabase_token",
            kSecAttrAccessGroup as String: "group.app.commonplace",
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            // Return demo token for testing
            return "demo_token"
        }

        return token
    }
}

enum ShareError: LocalizedError {
    case notAuthenticated
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to the Commonplace app first"
        case .saveFailed:
            return "Failed to save. Please try again."
        }
    }
}
