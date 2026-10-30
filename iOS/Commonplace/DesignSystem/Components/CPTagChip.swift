import SwiftUI

/// Compact chip for a tag name. Pass an `action` to make it tappable (filter rows);
/// leave it nil for a static label (detail screen).
struct CPTagChip: View {
    let name: String
    var isSelected: Bool = false
    /// Optional leading glyph (a source icon for source chips). Tags show their
    /// name alone; the hash prefix was dropped on 2026-10-28 as visual noise.
    var prefix: String = ""
    var action: (() -> Void)? = nil

    var body: some View {
        if let action = action {
            Button {
                HapticManager.selection()
                action()
            } label: {
                label
            }
            .buttonStyle(.plain)
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 2) {
            if !prefix.isEmpty {
                Text(prefix)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .cpTextSecondary)
            }

            Text(name)
        }
        .font(.cpCaption1)
        .fontWeight(.medium)
        .lineLimit(1)
        .padding(.horizontal, CPSpacing.xs)
        .padding(.vertical, CPSpacing.xxs)
        .background(isSelected ? Color.cpTint : Color.cpTint.opacity(0.1))
        .foregroundColor(isSelected ? .white : .cpTint)
        .cornerRadius(CPSpacing.cornerRadiusLarge)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: CPSpacing.sm) {
        FlowLayout(spacing: CPSpacing.xs) {
            CPTagChip(name: "Design Trends")
            CPTagChip(name: "AI")
            CPTagChip(name: "Startups")
        }

        HStack {
            CPTagChip(name: "Selected", isSelected: true) {}
            CPTagChip(name: "Unselected") {}
        }
    }
    .padding()
}
