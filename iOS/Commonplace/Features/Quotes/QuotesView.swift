import SwiftUI

/// Every quote the reader bookmarked, newest first. Tap one to open its save;
/// the bookmark removes it, the share button makes the Sangrah card.
struct QuotesView: View {
    @StateObject private var viewModel = QuotesViewModel()
    @ObservedObject private var service = SavedQuoteService.shared
    @State private var sharing: SavedQuote?
    @State private var path: [Document] = []

    var body: some View {
        NavigationStack(path: $path) {
            let quotes = viewModel.filtered(service.quotes)

            ScrollView {
                if quotes.isEmpty {
                    emptyState
                        .padding(.top, CPSpacing.xxxl)
                } else {
                    LazyVStack(spacing: CPSpacing.sm) {
                        ForEach(quotes) { quote in
                            if let document = quote.document {
                                // A tap gesture, not a NavigationLink, so the bookmark and
                                // share buttons inside the row keep their own taps
                                row(quote, document: document)
                                    .onTapGesture { path.append(document) }
                                    .accessibilityAddTraits(.isButton)
                            }
                        }
                    }
                    .padding(.horizontal, CPSpacing.screenHorizontal)
                    .padding(.vertical, CPSpacing.screenVertical)
                }
            }
            .navigationTitle("Quotes")
            .searchable(text: $viewModel.searchText, prompt: "Search your quotes")
            .navigationDestination(for: Document.self) { document in
                DocumentDetailView(document: document)
            }
            .refreshable {
                await service.load(force: true)
            }
            .task {
                await service.load()
            }
            .sheet(item: $sharing) { quote in
                if let document = quote.document {
                    QuoteShareSheet(quote: quote.shareable, document: document)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if service.isLoading && service.quotes.isEmpty {
            CPLoadingView()
        } else if viewModel.searchText.isEmpty {
            CPEmptyState(
                icon: "bookmark",
                title: "No saved quotes yet",
                message: "Tap the bookmark on a quote card, or select a line in an article and choose Save as Quote."
            )
        } else {
            CPEmptyState(
                icon: "magnifyingglass",
                title: "No matches",
                message: "No saved quote matches \u{201C}\(viewModel.searchText)\u{201D}."
            )
        }
    }

    private func row(_ quote: SavedQuote, document: Document) -> some View {
        HStack(alignment: .top, spacing: CPSpacing.sm) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.cpTint)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: CPSpacing.xs) {
                if !quote.isVerbatim {
                    Text("KEY IDEA")
                        .font(.cpCaption1)
                        .fontWeight(.semibold)
                        .tracking(1.2)
                        .foregroundColor(.cpTint)
                }

                let text = quote.shareable.displayText
                Text(quote.isVerbatim ? "\u{201C}\(text)\u{201D}" : text)
                    .font(.cpHeadline)
                    .italic()
                    .foregroundColor(.cpText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .bottom, spacing: CPSpacing.xs) {
                    QuoteCreditView(document: document, isVerbatim: quote.isVerbatim)
                    Spacer(minLength: CPSpacing.sm)
                    actions(quote)
                }
            }
        }
        .padding(CPSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cpBackgroundSecondary)
        .cornerRadius(CPSpacing.cornerRadiusLarge)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                UIPasteboard.general.string = quote.shareable.caption(for: document)
            } label: {
                Label("Copy Quote", systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                withAnimation { service.remove(quote) }
            } label: {
                Label("Remove from Quotes", systemImage: "bookmark.slash")
            }
        }
    }

    private func actions(_ quote: SavedQuote) -> some View {
        HStack(spacing: CPSpacing.md) {
            Button {
                withAnimation { service.remove(quote) }
            } label: {
                Image(systemName: "bookmark.fill")
            }
            .accessibilityLabel("Remove from saved quotes")

            Button {
                sharing = quote
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share this quote as an image")
        }
        .font(.system(size: 19, weight: .medium))
        .foregroundColor(.cpTint)
    }
}

#Preview {
    QuotesView()
}
