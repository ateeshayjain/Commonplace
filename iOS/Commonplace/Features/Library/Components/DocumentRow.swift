import SwiftUI

struct DocumentRow: View {
    let document: Document

    var body: some View {
        VStack(alignment: .leading, spacing: CPSpacing.xs) {
            // Author row
            HStack(spacing: CPSpacing.xs) {
                // Source icon
                SourceIcon(type: document.sourceType, size: 14)

                Text(document.authorName ?? document.sourceDomain ?? "Unknown")
                    .font(.cpHeadline)
                    .foregroundColor(.cpText)
                    .lineLimit(1)

                if let handle = document.authorHandle {
                    Text(handle)
                        .font(.cpSubhead)
                        .foregroundColor(.cpTextSecondary)
                        .lineLimit(1)
                }

                Text("·")
                    .foregroundColor(.cpTextSecondary)

                Text(document.createdAt.timeAgo)
                    .font(.cpSubhead)
                    .foregroundColor(.cpTextSecondary)

                Spacer()

                if document.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.yellow)
                }
            }

            // Title
            Text(document.title)
                .font(.cpBody)
                .fontWeight(.medium)
                .foregroundColor(.cpText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Summary
            if let summary = document.aiSummaryShort {
                Text(summary)
                    .font(.cpCallout)
                    .foregroundColor(.cpTextSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            } else if document.isWaitingForSummary {
                Label("Waiting for a summary", systemImage: "hourglass")
                    .font(.cpFootnote)
                    .foregroundColor(.cpTextSecondary)
            }

            // Footer
            HStack {
                // Categories
                if !document.userCategories.isEmpty {
                    Text(document.userCategories.prefix(2).joined(separator: " · "))
                        .font(.cpFootnote)
                        .foregroundColor(.cpTint)
                }

                Spacer()

                // Metadata
                HStack(spacing: CPSpacing.xs) {
                    if document.isThread, let total = document.threadTotal {
                        Label("\(total) posts", systemImage: "text.bubble")
                            .font(.cpFootnote)
                            .foregroundColor(.cpTextTertiary)
                    } else if let readTime = document.readingTimeMinutes {
                        Label("\(readTime) min", systemImage: "clock")
                            .font(.cpFootnote)
                            .foregroundColor(.cpTextTertiary)
                    }

                    // Progress indicator
                    if document.readProgress > 0 && document.readProgress < 1 {
                        ProgressView(value: document.readProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .cpTint))
                            .frame(width: 30)
                    }
                }

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.cpTextTertiary)
            }
        }
        .padding(.horizontal, CPSpacing.screenHorizontal)
        .padding(.vertical, CPSpacing.listItemVertical)
        .contentShape(Rectangle())
    }
}

// MARK: - Compact Row (for search results)

struct DocumentRowCompact: View {
    let document: Document

    var body: some View {
        HStack(spacing: CPSpacing.sm) {
            // Source icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(document.sourceType.color.opacity(0.1))
                    .frame(width: 40, height: 40)

                SourceIcon(type: document.sourceType, size: 18)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                    .font(.cpSubhead)
                    .fontWeight(.medium)
                    .foregroundColor(.cpText)
                    .lineLimit(1)

                HStack(spacing: CPSpacing.xxs) {
                    Text(document.authorName ?? "Unknown")
                        .font(.cpFootnote)
                        .foregroundColor(.cpTextSecondary)

                    Text("·")
                        .foregroundColor(.cpTextSecondary)

                    Text(document.createdAt.timeAgo)
                        .font(.cpFootnote)
                        .foregroundColor(.cpTextSecondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.cpTextTertiary)
        }
        .padding(.horizontal, CPSpacing.screenHorizontal)
        .padding(.vertical, CPSpacing.sm)
        .contentShape(Rectangle())
    }
}

#Preview {
    VStack(spacing: 0) {
        DocumentRow(document: .preview)
        Divider()
        DocumentRow(document: Document.previews[1])
        Divider()
        DocumentRowCompact(document: .preview)
    }
}
