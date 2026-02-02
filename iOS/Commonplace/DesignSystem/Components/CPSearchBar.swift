import SwiftUI

struct CPSearchBar: View {
    @Binding var text: String
    let placeholder: String
    var onSubmit: (() -> Void)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: CPSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.cpTextTertiary)
                .font(.system(size: 15))

            TextField(placeholder, text: $text)
                .font(.cpBody)
                .focused($isFocused)
                .onSubmit {
                    onSubmit?()
                }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !text.isEmpty {
                Button {
                    text = ""
                    HapticManager.buttonTap()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.cpTextTertiary)
                        .font(.system(size: 15))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// MARK: - Chip-style Search Bar

struct CPSearchChip: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: CPSpacing.xxs) {
            Text(text)
                .font(.cpSubhead)
                .foregroundColor(.cpTint)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.cpTint.opacity(0.6))
            }
        }
        .padding(.horizontal, CPSpacing.sm)
        .padding(.vertical, CPSpacing.xs)
        .background(Color.cpTint.opacity(0.1))
        .cornerRadius(CPSpacing.cornerRadiusLarge)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        CPSearchBar(text: .constant(""), placeholder: "Search your library")
        CPSearchBar(text: .constant("technology"), placeholder: "Search your library")

        HStack {
            CPSearchChip(text: "Technology") {}
            CPSearchChip(text: "AI") {}
        }
    }
    .padding()
}
