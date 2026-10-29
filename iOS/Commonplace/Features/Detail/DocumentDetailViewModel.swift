import Foundation
import SwiftUI

@MainActor
class DocumentDetailViewModel: ObservableObject {
    @Published var document: Document
    @Published var selectedCategories: Set<String>
    @Published var tags: [Tag] = []
    @Published var isLoading = false
    @Published var error: Error?
    /// Set once the document is gone, so the view can close itself.
    @Published var isDeleted = false
    @Published var isPreparingPDF = false
    /// A file ready to hand to the share sheet.
    @Published var sharedFile: SharedFile?
    /// A file ready to open in the in-app PDF reader.
    @Published var viewedFile: SharedFile?

    struct SharedFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    private let documentService = DocumentService.shared

    init(document: Document) {
        self.document = document
        self.selectedCategories = Set(document.userCategories)
    }

    // MARK: - Tags

    func loadTags() async {
        // Demo mode: derive tags from the document's AI topics
        if let user = AuthService.shared.currentUser, user.email == "demo@commonplace.app" {
            tags = documentService.demoTags(for: [document], userId: user.id)
            return
        }

        do {
            tags = try await documentService.fetchTags(for: document.id)
        } catch {
            // Tags are supplementary; don't surface the error over the document
            tags = []
        }
    }

    // MARK: - Actions

    func toggleFavorite() {
        Task {
            do {
                try await documentService.toggleFavorite(document.id, isFavorite: !document.isFavorite)
                document.isFavorite.toggle()
                HapticManager.saveSuccess()
            } catch {
                self.error = error
                HapticManager.error()
            }
        }
    }

    func updateCategories() {
        Task {
            do {
                let categories = Array(selectedCategories)
                try await documentService.updateCategories(document.id, categories: categories)
                document.userCategories = categories
                HapticManager.saveSuccess()
            } catch {
                self.error = error
                HapticManager.error()
            }
        }
    }

    func updateNotes(_ notes: String) {
        Task {
            do {
                try await documentService.updateNotes(document.id, notes: notes)
                document.userNotes = notes
                HapticManager.saveSuccess()
            } catch {
                self.error = error
                HapticManager.error()
            }
        }
    }

    func updateReadProgress(_ progress: Double) {
        Task {
            do {
                try await documentService.updateReadProgress(document.id, progress: progress)
                document.readProgress = progress
            } catch {
                self.error = error
            }
        }
    }

    func deleteDocument() {
        Task {
            do {
                // Demo documents live only in memory
                if AuthService.shared.currentUser?.email != "demo@commonplace.app" {
                    try await documentService.deleteDocument(document.id)
                }
                HapticManager.deleteWarning()
                NotificationCenter.default.post(name: .documentDeleted, object: document.id)
                isDeleted = true
            } catch {
                self.error = error
                HapticManager.error()
            }
        }
    }

    func sharePDF() {
        preparePDF { [weak self] file in self?.sharedFile = SharedFile(url: file) }
    }

    func openPDF() {
        preparePDF { [weak self] file in self?.viewedFile = SharedFile(url: file) }
    }

    private func preparePDF(then present: @escaping (URL) -> Void) {
        guard !isPreparingPDF else { return }
        if AuthService.shared.currentUser?.email == "demo@commonplace.app" {
            error = PDFShareError.demoMode
            return
        }
        isPreparingPDF = true
        Task {
            defer { isPreparingPDF = false }
            do {
                let file = try await documentService.pdfFile(for: document)
                present(file)
            } catch {
                self.error = PDFShareError.failed
                HapticManager.error()
            }
        }
    }

    func archiveDocument() {
        Task {
            do {
                try await documentService.archiveDocument(document.id, isArchived: true)
                document.isArchived = true
                HapticManager.saveSuccess()
            } catch {
                self.error = error
                HapticManager.error()
            }
        }
    }
}

enum PDFShareError: LocalizedError {
    case demoMode
    case failed

    var errorDescription: String? {
        switch self {
        case .demoMode: return "Sign in to share items as PDF."
        case .failed: return "Couldn't create the PDF. Please try again."
        }
    }
}
