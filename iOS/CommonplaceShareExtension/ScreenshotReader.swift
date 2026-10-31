import UIKit
import Vision

/// Reads shared screenshots on the device with Apple's text recognition, for
/// free accounts: nothing is uploaded and Claude isn't involved. The pages
/// are joined into one article by ScreenshotText (Shared/).
enum ScreenshotReader {
    /// Large enough for small text; the share extension has little memory, so
    /// images are read one at a time from a downscaled copy
    private static let maxPixels = 2600

    static func article(from providers: [NSItemProvider], progress: @MainActor (Int) -> Void) async -> ScreenshotText.Article {
        var pages: [[OCRLine]] = []
        for (index, provider) in providers.enumerated() {
            await progress(index)
            guard let image = await ShareExtensionService.downscaledImage(from: provider, maxPixels: maxPixels) else { continue }
            let lines = await Task.detached(priority: .userInitiated) { (try? recognise(image)) ?? [] }.value
            pages.append(lines)
        }
        return ScreenshotText.article(from: pages)
    }

    /// The image's lines, top to bottom positions measured from the top edge
    static func recognise(_ image: CGImage) throws -> [OCRLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // English and Hindi where this iOS version reads both
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let languages = ["en-US", "hi-IN"].filter(supported.contains)
        request.recognitionLanguages = languages.isEmpty ? ["en-US"] : languages

        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
        } catch where languages.count > 1 {
            // Some versions refuse the combination; English alone still reads most saves
            request.recognitionLanguages = ["en-US"]
            try VNImageRequestHandler(cgImage: image).perform([request])
        }

        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            // Vision's boxes are normalised with the origin at the bottom left
            let box = observation.boundingBox
            return OCRLine(text: text, top: 1 - box.maxY, bottom: 1 - box.minY)
        }
    }
}
