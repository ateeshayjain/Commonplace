import SwiftUI

struct CategoryFilterView: View {
    let categories: [Category]
    @Binding var selected: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CPSpacing.xs) {
                // "All" pill
                CategoryPill(
                    name: "All",
                    icon: nil,
                    isSelected: selected == nil
                ) {
                    selected = nil
                }

                // Category pills
                ForEach(categories) { category in
                    CategoryPill(
                        name: category.name,
                        icon: category.icon,
                        isSelected: selected == category.name
                    ) {
                        if selected == category.name {
                            selected = nil
                        } else {
                            selected = category.name
                        }
                    }
                }
            }
            .padding(.horizontal, CPSpacing.screenHorizontal)
        }
    }
}

// MARK: - Category Selection Sheet

struct CategorySelectionSheet: View {
    let categories: [Category]
    @Binding var selectedCategories: Set<String>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(categories) { category in
                    Button {
                        if selectedCategories.contains(category.name) {
                            selectedCategories.remove(category.name)
                        } else {
                            selectedCategories.insert(category.name)
                        }
                        HapticManager.selection()
                    } label: {
                        HStack {
                            if let icon = category.icon {
                                Text(icon)
                                    .font(.system(size: 20))
                            }

                            Text(category.name)
                                .font(.cpBody)
                                .foregroundColor(.cpText)

                            Spacer()

                            if selectedCategories.contains(category.name) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.cpTint)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Category Badge

struct CategoryBadge: View {
    let name: String
    let color: Color

    var body: some View {
        Text(name)
            .font(.cpCaption1)
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, CPSpacing.xs)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .cornerRadius(4)
    }
}

#Preview {
    VStack {
        CategoryFilterView(
            categories: Category.systemCategories,
            selected: .constant(nil)
        )

        CategoryFilterView(
            categories: Category.systemCategories,
            selected: .constant("Technology")
        )

        HStack {
            CategoryBadge(name: "Technology", color: .cpTechnology)
            CategoryBadge(name: "Business", color: .cpBusiness)
        }
    }
}
