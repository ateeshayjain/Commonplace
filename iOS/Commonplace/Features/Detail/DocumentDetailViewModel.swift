import Foundation
import SwiftUI

@MainActor
class DocumentDetailViewModel: ObservableObject {
    @Published var document: Document
    @Published var selectedCategories: Set<String>
    @Published var tags: [Tag] = []
    @Published var isLoading = false
    @Published var error: Error?

    private let documentService = DocumentService.shared

    init(document: Document) {
        self.document = document
        self.selectedCategories = Set(document.userCategories)
    }

    // MARK: - Tags

    func loadTags() async {
        // Demo mode: derive tags from the document's AI topics
        if AuthService.shared.currentUser?.email == "demo@commonplace.app" {
            tags = documentService.demoTags(for: [document])
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
                try await documentService.deleteDocument(document.id)
                HapticManager.deleteWarning()
                // Navigation back would be handled by the view
            } catch {
                self.error = error
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
