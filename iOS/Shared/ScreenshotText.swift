import Foundation

/// One line of text read from a screenshot, with where it sits on the image
/// (0 = top edge, 1 = bottom edge)
struct OCRLine: Equatable {
    let text: String
    let top: Double
    let bottom: Double
}

/// Joins the text read from several screenshots of one piece into a single
/// article. Free accounts read screenshots on the device (the Share Extension,
/// with Vision); Pro screenshots are read by Claude on the server instead.
/// Compiled into the app (for tests) and the Share Extension.
enum ScreenshotText {
    struct Article: Equatable {
        let title: String
        let body: String
    }

    static let defaultTitle = "Saved screenshots"
    /// A first paragraph longer than this is body text, not a headline
    static let maxTitleLength = 100

    /// Pages in the order the screenshots were picked
    static func article(from pages: [[OCRLine]]) -> Article {
        let paragraphs = paragraphs(from: merge(pages.map(lines(from:))))
        let first = paragraphs.first ?? ""
        let title = !first.isEmpty && first.count <= maxTitleLength ? first : defaultTitle
        return Article(title: title, body: paragraphs.joined(separator: "\n\n"))
    }

    // MARK: - Lines on one page

    struct Line: Equatable {
        let text: String
        /// nil for a page's first line, where the gap above it isn't known
        let startsParagraph: Bool?
    }

    /// The page's lines top to bottom, without the phone's chrome, each marked
    /// with whether the gap above it opens a new paragraph
    static func lines(from page: [OCRLine]) -> [Line] {
        let kept = page
            .map { OCRLine(text: $0.text.trimmingCharacters(in: .whitespaces), top: $0.top, bottom: $0.bottom) }
            .filter { !$0.text.isEmpty && !isChrome($0) }
            .sorted { $0.top < $1.top }
        let heights = kept.map { $0.bottom - $0.top }.sorted()
        let lineHeight = heights.isEmpty ? 0 : heights[heights.count / 2]

        return kept.enumerated().map { index, line in
            guard index > 0 else { return Line(text: line.text, startsParagraph: nil) }
            // Wrapped lines sit close together; a paragraph break leaves a taller gap
            let gap = line.top - kept[index - 1].bottom
            return Line(text: line.text, startsParagraph: gap > lineHeight * 0.8)
        }
    }

    /// The status bar (clock, battery, carrier), a tab bar along the bottom,
    /// and stray single characters
    static func isChrome(_ line: OCRLine) -> Bool {
        let text = line.text
        if text.count <= 1 { return true }
        if line.top < 0.06 && text.count < 25 { return true }
        if line.bottom > 0.95 && text.count < 30 { return true }
        if text.range(of: #"^\d{1,2}[:.]\d{2}(\s?[AaPp]\.?[Mm]\.?)?$"#, options: .regularExpression) != nil { return true }
        if text.range(of: #"^\d{1,3}\s?%$"#, options: .regularExpression) != nil { return true }
        return false
    }

    // MARK: - Joining pages

    /// One run of lines, with what consecutive screenshots share written once
    static func merge(_ pages: [[Line]]) -> [Line] {
        var result: [Line] = []
        for page in pages where !page.isEmpty {
            guard let previous = result.last else {
                result = page
                continue
            }
            let shared = overlap(result, page)
            result.removeLast(shared.dropLast)
            var rest = Array(page.dropFirst(shared.dropFirst))
            if let first = rest.first, first.startsParagraph == nil {
                let last = result.last ?? previous
                rest[0] = Line(text: first.text, startsParagraph: !continues(last.text, with: first.text))
            }
            result += rest
        }
        return result
    }

    struct Overlap: Equatable {
        /// Lines to drop from the end of the text so far (a line cut off by the bottom edge)
        var dropLast = 0
        /// Lines to drop from the start of the next page (the shared lines, plus
        /// a line cut off by the top edge)
        var dropFirst = 0
    }

    /// The lines at the bottom of what's been read that reappear at the top
    /// of the next screenshot. Allows one cut-off line on either edge, and
    /// trusts a single shared line only when it's long enough to be distinctive.
    static func overlap(_ earlier: [Line], _ next: [Line], maxLines: Int = 25) -> Overlap {
        let a = earlier.map { key($0.text) }
        let b = next.map { key($0.text) }
        var best = Overlap()
        var bestCount = 0
        for cutBottom in 0...min(1, a.count) {
            for cutTop in 0...min(1, b.count) {
                let available = min(a.count - cutBottom, b.count - cutTop, maxLines)
                let minimum = cutBottom + cutTop == 0 ? 1 : 2
                guard available >= minimum else { continue }
                for count in stride(from: available, through: minimum, by: -1) where count > bestCount {
                    let tail = a[(a.count - cutBottom - count)..<(a.count - cutBottom)]
                    let head = b[cutTop..<(cutTop + count)]
                    guard Array(tail) == Array(head) else { continue }
                    if count == 1 && head.first!.count < 20 { continue }
                    best = Overlap(dropLast: cutBottom, dropFirst: cutTop + count)
                    bestCount = count
                    break
                }
            }
        }
        return best
    }

    /// OCR text compared for overlap: letters, marks and digits only, lowercased
    /// (keeps Devanagari vowel signs and viramas)
    static func key(_ text: String) -> String {
        String(String.UnicodeScalarView(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    }

    /// Whether the next screenshot's first line carries on the sentence the
    /// previous one ended on
    static func continues(_ previous: String, with next: String) -> Bool {
        if previous.hasSuffix("-") { return true }
        guard let last = previous.last, let first = next.first else { return false }
        if ".!?:\"”’)".contains(last) { return false }
        return first.isLowercase
    }

    // MARK: - Paragraphs

    static func paragraphs(from lines: [Line]) -> [String] {
        var paragraphs: [String] = []
        var current = ""
        for line in lines {
            if current.isEmpty {
                current = line.text
            } else if line.startsParagraph ?? true {
                paragraphs.append(current)
                current = line.text
            } else if current.hasSuffix("-"), line.text.first?.isLowercase == true {
                // A word hyphenated across lines
                current = String(current.dropLast()) + line.text
            } else {
                current += " " + line.text
            }
        }
        if !current.isEmpty { paragraphs.append(current) }
        return paragraphs
    }
}
