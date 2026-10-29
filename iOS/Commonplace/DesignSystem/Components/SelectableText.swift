import SwiftUI
import UIKit

// MARK: - Selectable Text

/// Read-only text whose selection menu has extra actions next to Copy and
/// Look Up (SwiftUI's `.textSelection` can't add any). Backed by a
/// non-scrolling UITextView that sizes itself to the proposed width.
struct SelectableText: UIViewRepresentable {
    struct MenuAction {
        let title: String
        let systemImage: String
        let handler: (String) -> Void
    }

    let text: String
    /// nil shows every line
    var lineLimit: Int?
    var actions: [MenuAction] = []

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.font = .systemFont(ofSize: 17) // cpBody
        view.textColor = .label // cpText
        view.adjustsFontForContentSizeCategory = true
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.actions = actions
        if view.text != text {
            view.text = text
        }
        view.textContainer.maximumNumberOfLines = lineLimit ?? 0
        view.textContainer.lineBreakMode = lineLimit == nil ? .byWordWrapping : .byTruncatingTail
        view.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UITextViewDelegate {
        var actions: [MenuAction] = []

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let selected = (textView.text as NSString?)?.substring(with: range),
                  !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !actions.isEmpty else { return nil }

            let custom = actions.map { action in
                UIAction(title: action.title, image: UIImage(systemName: action.systemImage)) { _ in
                    action.handler(selected)
                    textView.selectedTextRange = nil
                }
            }
            // Ours first, so they show without scrolling the menu
            return UIMenu(children: custom + suggestedActions)
        }
    }
}
