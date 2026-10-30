import Foundation

/// The reader's categories: the built-in ones plus any they add in Profile >
/// Manage Categories. Shared by the Library filter chips, the category picker
/// on a save and Manage Categories. Changes show at once and are rolled back
/// if the server refuses them.
@MainActor
final class CategoryService: ObservableObject {
    static let shared = CategoryService()

    /// Built-in first, then the reader's own, each in sort order
    @Published private(set) var categories: [Category] = Category.systemCategories
    @Published var error: Error?

    private let supabase = SupabaseService.shared
    /// Whose categories `categories` holds, so a different sign-in starts from the built-in list
    private var loadedUserId: UUID?

    private var isDemo: Bool {
        AuthService.shared.currentUser?.email == "demo@commonplace.app"
    }

    private init() {}

    // MARK: - Reading

    func load(force: Bool = false) async {
        let userId = AuthService.shared.currentUser?.id
        if loadedUserId != userId {
            categories = Category.systemCategories
            loadedUserId = nil
        }
        guard force || loadedUserId == nil, let userId else { return }

        // Demo categories live only in memory
        if isDemo {
            loadedUserId = userId
            return
        }

        do {
            // RLS returns the built-in rows (user_id null) and this reader's own
            let rows: [Category] = try await supabase.fetch(from: "categories", order: "sort_order.asc")
            if !rows.isEmpty {
                categories = rows.sorted { ($0.isSystem ? 0 : 1, $0.sortOrder) < ($1.isSystem ? 0 : 1, $1.sortOrder) }
            }
            loadedUserId = userId
        } catch {
            // Keep the built-in list so the filters still work
            self.error = error
        }
    }

    // MARK: - Changes

    /// Adds a category; false when the name is empty or matches an existing one
    @discardableResult
    func add(named rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = Self.slug(for: name)
        guard !slug.isEmpty,
              !categories.contains(where: { $0.slug == slug }),
              let userId = AuthService.shared.currentUser?.id else { return false }

        let category = Category(
            id: UUID(),
            userId: userId,
            name: name,
            slug: slug,
            icon: "📁",
            color: "#5856D6",
            isSystem: false,
            sortOrder: (categories.map(\.sortOrder).max() ?? 0) + 1
        )
        categories.append(category)
        guard !isDemo else { return true }

        Task {
            do {
                _ = try await supabase.insert(into: "categories", values: category)
            } catch {
                categories.removeAll { $0.id == category.id }
                self.error = error
            }
        }
        return true
    }

    /// Removes one of the reader's own categories. Built-in ones stay. Saves
    /// already filed under it keep the label.
    func remove(_ category: Category) {
        guard !category.isSystem, let index = categories.firstIndex(of: category) else { return }
        categories.remove(at: index)
        guard !isDemo else { return }

        Task {
            do {
                try await supabase.delete(from: "categories", id: category.id)
            } catch {
                categories.insert(category, at: min(index, categories.count))
                self.error = error
            }
        }
    }

    /// "Design Trends" and "design-trends" are the same category
    static func slug(for name: String) -> String {
        name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}
