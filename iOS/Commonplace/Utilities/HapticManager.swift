import UIKit

enum HapticManager {
    // MARK: - Impact Feedback

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    // MARK: - Notification Feedback

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }

    // MARK: - Selection Feedback

    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    // MARK: - Semantic Haptics

    /// Light tap for button presses
    static func buttonTap() {
        impact(.light)
    }

    /// Medium impact for toggles
    static func toggleChange() {
        impact(.medium)
    }

    /// Success notification
    static func saveSuccess() {
        notification(.success)
    }

    /// Warning notification
    static func deleteWarning() {
        notification(.warning)
    }

    /// Error notification
    static func error() {
        notification(.error)
    }

    /// Heavy impact for long press
    static func longPressBegin() {
        impact(.heavy)
    }

    /// Soft impact for menu opening
    static func menuOpen() {
        impact(.soft)
    }

    /// Rigid impact for snapping
    static func snap() {
        impact(.rigid)
    }
}
