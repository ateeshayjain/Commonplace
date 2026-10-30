import SwiftUI
import PDFKit

struct PDFViewerView: View {
    let url: URL
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var error: Error?
    @State private var pdfDocument: PDFDocument?
    @State private var showingShareSheet = false
    @State private var showingSaveToFiles = false

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
                            showingShareSheet = true
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            showingSaveToFiles = true
                        } label: {
                            Label("Save to Files", systemImage: "folder")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(pdfDocument == nil)
                }
            }
            // Presented from this screen: the viewer is itself a full-screen cover,
            // and the app's root controller can't present while it is showing
            .sheet(isPresented: $showingShareSheet) {
                ActivityView(items: [url])
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showingSaveToFiles) {
                SaveToFilesView(url: url)
                    .ignoresSafeArea()
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

// MARK: - Save to Files

/// The system "Save to Files" picker for a local file; saves a copy wherever the user chooses
struct SaveToFilesView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
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
