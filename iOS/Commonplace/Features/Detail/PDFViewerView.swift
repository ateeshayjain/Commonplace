import SwiftUI
import PDFKit

struct PDFViewerView: View {
    let url: URL
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var error: Error?
    @State private var pdfDocument: PDFDocument?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    CPLoadingView("Loading PDF...")
                } else if let error = error {
                    VStack(spacing: CPSpacing.md) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48, weight: .ultraLight))
                            .foregroundColor(.cpTextTertiary)

                        Text("Failed to load PDF")
                            .font(.cpTitle3)

                        Text(error.localizedDescription)
                            .font(.cpCallout)
                            .foregroundColor(.cpTextSecondary)
                            .multilineTextAlignment(.center)

                        CPButton("Try Again", style: .secondary) {
                            Task {
                                await loadPDF()
                            }
                        }
                    }
                    .padding()
                } else if let pdfDocument = pdfDocument {
                    PDFKitView(document: pdfDocument)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            sharePDF()
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            // Download for offline
                        } label: {
                            Label("Save for Offline", systemImage: "arrow.down.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task {
            await loadPDF()
        }
    }

    private func loadPDF() async {
        isLoading = true
        error = nil

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let document = PDFDocument(data: data) {
                pdfDocument = document
            } else {
                error = PDFError.invalidPDF
            }
        } catch {
            self.error = error
        }

        isLoading = false
    }

    private func sharePDF() {
        guard let pdfDocument = pdfDocument,
              let data = pdfDocument.dataRepresentation() else {
            return
        }

        let activityVC = UIActivityViewController(
            activityItems: [data],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - PDFKit View

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = UIColor.systemBackground
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = document
    }
}

// MARK: - PDF Error

enum PDFError: LocalizedError {
    case invalidPDF
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .invalidPDF:
            return "The PDF file is invalid or corrupted."
        case .downloadFailed:
            return "Failed to download the PDF."
        }
    }
}

#Preview {
    PDFViewerView(
        url: URL(string: "https://example.com/sample.pdf")!,
        title: "Sample PDF"
    )
}
