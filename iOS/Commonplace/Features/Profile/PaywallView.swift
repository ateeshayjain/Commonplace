import SwiftUI
import StoreKit

/// Sangrah Pro: shown from Profile's Upgrade row, a save's Smart summary card,
/// the 6th save of the day, and Compose. Prices and the free month come from
/// the App Store; the server confirms the purchase before Pro switches on.
struct PaywallView: View {
    enum Reason {
        case upgrade
        case summary
        case dailyLimit
        case compose

        var headline: String {
            switch self {
            case .upgrade: return "Get more from what you save"
            case .summary: return "Smart summaries are part of Pro"
            case .dailyLimit: return "You've saved 5 articles today"
            case .compose: return "Compose is part of Sangrah Pro"
            }
        }
    }

    var reason: Reason = .upgrade

    @ObservedObject private var subscriptions = SubscriptionService.shared
    @State private var selected: SubscriptionProduct = .yearly
    @Environment(\.dismiss) private var dismiss

    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CPSpacing.lg) {
                    header
                    comparison
                    whyItCosts
                    if subscriptions.products.isEmpty {
                        unavailable
                    } else {
                        planPicker
                        purchaseSection
                    }
                    footer
                }
                .padding(.horizontal, CPSpacing.screenHorizontal)
                .padding(.vertical, CPSpacing.screenVertical)
            }
            .background(Color.cpBackground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                }
            }
            .alert("Purchase", isPresented: .init(
                get: { subscriptions.error != nil },
                set: { if !$0 { subscriptions.error = nil } }
            )) {
                Button("OK", role: .cancel) { subscriptions.error = nil }
            } message: {
                Text(subscriptions.error?.localizedDescription ?? "Something went wrong.")
            }
            .task { await subscriptions.loadProducts() }
            .onChange(of: subscriptions.plan?.isPro) { _, isPro in
                if isPro == true { dismiss() }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: CPSpacing.xs) {
            Label("Sangrah Pro", systemImage: "sparkles")
                .font(.cpHeadline)
                .foregroundColor(.cpTint)
            Text(reason.headline)
                .font(.cpTitle1)
                .foregroundColor(.cpText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Free vs Pro, in plain words
    private var comparison: some View {
        VStack(spacing: 0) {
            comparisonRow("", free: "Free", pro: "Pro", isHeader: true)
            comparisonRow("Saves", free: "5 a day", pro: "Unlimited")
            comparisonRow("Clean article, PDF, Listen, search", free: "check", pro: "check")
            comparisonRow("Smart summary: Key Idea, summary, key points", free: "", pro: "check")
            comparisonRow("Quotes to share as cards, tags, categories", free: "", pro: "check")
            comparisonRow("Screenshots", free: "Read on iPhone", pro: "Read by Claude")
            comparisonRow("Compose posts and articles", free: "", pro: "10 a month")
        }
        .background(
            RoundedRectangle(cornerRadius: CPSpacing.cornerRadiusMedium)
                .fill(Color.cpBackgroundSecondary)
        )
    }

    private func comparisonRow(_ feature: String, free: String, pro: String, isHeader: Bool = false) -> some View {
        HStack(spacing: CPSpacing.sm) {
            Text(feature)
                .font(.cpFootnote)
                .foregroundColor(.cpText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            comparisonCell(free, isHeader: isHeader, highlighted: false)
            comparisonCell(pro, isHeader: isHeader, highlighted: true)
        }
        .padding(.horizontal, CPSpacing.md)
        .padding(.vertical, CPSpacing.xs)
    }

    @ViewBuilder
    private func comparisonCell(_ value: String, isHeader: Bool, highlighted: Bool) -> some View {
        Group {
            switch value {
            case "check":
                Image(systemName: "checkmark")
                    .foregroundColor(highlighted ? .cpTint : .cpTextSecondary)
                    .accessibilityLabel("Included")
            case "":
                Image(systemName: "minus")
                    .foregroundColor(.cpTextTertiary)
                    .accessibilityLabel("Not included")
            default:
                Text(value)
                    .font(isHeader ? .cpHeadline : .cpCaption1)
                    .foregroundColor(highlighted ? .cpTint : .cpTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: 76)
    }

    private var whyItCosts: some View {
        VStack(alignment: .leading, spacing: CPSpacing.xxs) {
            Text(ProCopy.whyItCostsQuestion)
                .font(.cpHeadline)
                .foregroundColor(.cpText)
            Text(ProCopy.whyItCosts)
                .font(.cpFootnote)
                .foregroundColor(.cpTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var planPicker: some View {
        VStack(spacing: CPSpacing.sm) {
            ForEach(SubscriptionProduct.allCases, id: \.self) { kind in
                if let product = subscriptions.product(kind) {
                    planRow(kind, product)
                }
            }
        }
    }

    private func planRow(_ kind: SubscriptionProduct, _ product: Product) -> some View {
        let isSelected = selected == kind
        return Button {
            selected = kind
            HapticManager.selection()
        } label: {
            HStack(spacing: CPSpacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? .cpTint : .cpTextTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: CPSpacing.xs) {
                        Text(kind.title)
                            .font(.cpHeadline)
                            .foregroundColor(.cpText)
                        if kind == .yearly, let savings = yearlySavings {
                            Text("Save \(savings)%")
                                .font(.cpCaption1)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, CPSpacing.xs)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.cpTint))
                        }
                    }
                    Text(kind == .yearly ? "\(product.displayPrice) a year" : "\(product.displayPrice) a month")
                        .font(.cpSubhead)
                        .foregroundColor(.cpTextSecondary)
                }
                Spacer()
            }
            .padding(CPSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: CPSpacing.cornerRadiusMedium)
                    .stroke(isSelected ? Color.cpTint : Color.cpTextTertiary.opacity(0.4), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var purchaseSection: some View {
        VStack(alignment: .leading, spacing: CPSpacing.sm) {
            if let product = subscriptions.product(selected) {
                CPButton(
                    subscriptions.isTrialEligible ? "Start Free Month" : "Subscribe",
                    isLoading: subscriptions.isPurchasing
                ) {
                    Task { await subscriptions.purchase(product) }
                }
                Text(priceTerms(product))
                    .font(.cpFootnote)
                    .foregroundColor(.cpTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var unavailable: some View {
        CPCard {
            VStack(alignment: .leading, spacing: CPSpacing.sm) {
                Text("Plans aren't available right now")
                    .font(.cpHeadline)
                Text("Check your connection and try again.")
                    .font(.cpCallout)
                    .foregroundColor(.cpTextSecondary)
                CPButton("Try Again", style: .secondary, size: .medium) {
                    Task { await subscriptions.loadProducts() }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: CPSpacing.sm) {
            Button {
                Task { await subscriptions.restore() }
            } label: {
                if subscriptions.isRestoring {
                    ProgressView()
                } else {
                    Text("Restore Purchases")
                }
            }
            .font(.cpSubhead)
            .disabled(subscriptions.isRestoring)

            HStack(spacing: CPSpacing.md) {
                Link("Terms of Use", destination: termsURL)
                NavigationLink("Privacy Policy") { PrivacyPolicyView() }
            }
            .font(.cpCaption1)
            .foregroundColor(.cpTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private var yearlySavings: Int? {
        guard let monthly = subscriptions.product(.monthly), let yearly = subscriptions.product(.yearly) else { return nil }
        return SubscriptionProduct.yearlySavingsPercent(monthly: monthly.price, yearly: yearly.price)
    }

    /// The terms right under the button: what it costs after the free month,
    /// when the reminder comes, and how to cancel
    private func priceTerms(_ product: Product) -> String {
        let period = selected == .yearly ? "year" : "month"
        if subscriptions.isTrialEligible {
            return "Free for 1 month, then \(product.displayPrice) a \(period). We'll remind you \(TrialReminder.daysBefore) days before the free month ends. Renews automatically until you cancel in Settings > Apple ID > Subscriptions."
        }
        return "\(product.displayPrice) a \(period). Renews automatically until you cancel in Settings > Apple ID > Subscriptions."
    }
}

#Preview {
    PaywallView(reason: .dailyLimit)
}
