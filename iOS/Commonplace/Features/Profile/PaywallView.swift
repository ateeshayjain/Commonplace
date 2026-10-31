import SwiftUI
import StoreKit

/// Sangrah Pro: shown from Profile's Upgrade row, from a save waiting for an
/// AI credit, and from Compose. Prices and the free month come from the App
/// Store; the server confirms the purchase before Pro switches on.
struct PaywallView: View {
    enum Reason {
        case upgrade
        case saves
        case compose

        var headline: String {
            switch self {
            case .upgrade: return "Get more from what you save"
            case .saves: return "You've used this month's free AI saves"
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
                    benefits
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

    private var benefits: some View {
        VStack(alignment: .leading, spacing: CPSpacing.sm) {
            benefit("infinity", "Unlimited AI summaries", "Free accounts get 20 a month")
            benefit("text.quote", "Sharper summaries and quotes", "Every save read by Claude Sonnet")
            benefit("square.and.pencil", "Compose", "Turn several saves into posts, threads and articles, 10 times a month")
            benefit("books.vertical", "Everything else stays free", "Library, search, quotes, PDFs, the widget and your Weekly Summary")
        }
    }

    private func benefit(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: CPSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.cpTint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.cpHeadline)
                    .foregroundColor(.cpText)
                Text(detail)
                    .font(.cpFootnote)
                    .foregroundColor(.cpTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
    PaywallView(reason: .saves)
}
