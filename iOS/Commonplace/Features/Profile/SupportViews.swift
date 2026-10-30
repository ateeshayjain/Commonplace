import SwiftUI

// MARK: - Support Contact

/// Where Contact Support sends people, with the app version filled in so a reply knows which build they're on
enum SupportContact {
    static let email = "Ateeshay.jain@gmail.com"

    /// "Sangrah 1.0 (23)"
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Sangrah \(version) (\(build))"
    }

    private static let subject = "Sangrah support"

    private static var body: String {
        let device = UIDevice.current
        return "\n\n\n\u{2014}\n\(appVersion) \u{00B7} \(device.systemName) \(device.systemVersion) \u{00B7} \(device.model)"
    }

    static var mailURL: URL? {
        URL(string: "mailto:\(email)?subject=\(encode(subject))&body=\(encode(body))")
    }

    static var gmailURL: URL? {
        URL(string: "googlegmail:///co?to=\(email)&subject=\(encode(subject))&body=\(encode(body))")
    }

    /// Query-safe, with & = + ? escaped too so they can't split the parameters
    private static func encode(_ text: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}

// MARK: - FAQ

struct FAQView: View {
    private struct Item: Identifiable {
        let question: String
        let answer: String
        var id: String { question }
    }

    private let items: [Item] = [
        Item(question: "How do I save something?",
             answer: "In any app, tap Share and choose Sangrah. Links from Safari, X, Instagram, LinkedIn, Substack, Medium, YouTube and most websites work. If Sangrah isn't in the row of apps, scroll to the end, tap More and add it."),
        Item(question: "Can I save screenshots?",
             answer: "Yes. Select up to 10 screenshots in Photos, tap Share and choose Sangrah. They're read in order and combined into one save, with a summary and a PDF."),
        Item(question: "How long does a save take?",
             answer: "Usually under a minute. Sangrah reads the page, cleans it up and writes a summary, key points, tags and quotes. It appears in your Library when it's done."),
        Item(question: "How do I save a quote?",
             answer: "Open a save, select a passage in the Content section and choose Save as Quote. You can also tap the bookmark on any quote card. All your quotes are in the Quotes tab."),
        Item(question: "How do I share a quote?",
             answer: "Tap the share icon on a quote card. You get an image of the quote, and a caption with the title, author and link. For Instagram, the caption is copied so you can paste it into the post."),
        Item(question: "Where is the PDF?",
             answer: "Tap Read Full Article on any save to open a clean PDF. From its \u{22EF} menu you can share it or save it to Files."),
        Item(question: "Why is a save incomplete?",
             answer: "Some sites block readers or only show the full text after you sign in, like paywalled articles or Scribd. YouTube saves don't include the transcript yet. Screenshots of the page are a good fallback."),
        Item(question: "What does search look at?",
             answer: "The Library search box matches titles, authors, the article text, your notes, tags, key points and quotes. The Quotes tab has its own search."),
        Item(question: "How do I delete a save?",
             answer: "Open it, tap \u{22EF} and choose Delete."),
        Item(question: "Is Sangrah free?",
             answer: "Yes. During the beta everything is free, with no limits.")
    ]

    var body: some View {
        List(items) { item in
            DisclosureGroup {
                Text(item.answer)
                    .font(.cpBody)
                    .foregroundColor(.cpTextSecondary)
                    .padding(.vertical, CPSpacing.xxs)
            } label: {
                Text(item.question)
                    .font(.cpHeadline)
                    .foregroundColor(.cpText)
            }
        }
        .navigationTitle("FAQ")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Privacy Policy

struct PrivacyPolicyView: View {
    private struct Part: Identifiable {
        let heading: String
        let text: String
        var id: String { heading }
    }

    private let parts: [Part] = [
        Part(heading: "What Sangrah stores",
             text: "Your account: your email address and, if you use Sign in with Apple, the name Apple shares. What you save: links, the text Sangrah reads from them, screenshots you share, and your notes, categories, tags and quotes. Sangrah also stores the PDFs it makes from your saves."),
        Part(heading: "How your saves are processed",
             text: "Your data is stored with Supabase, which also handles sign-in. To read a link, Sangrah fetches the page directly or through a reader service (Jina Reader for articles, FxTwitter for posts on X). The text, or the screenshots, is then sent to Anthropic's Claude API to write the summary, key points, tags and quotes. Under Anthropic's commercial terms, this data isn't used to train its models."),
        Part(heading: "Who can see it",
             text: "Only you. Your saves, notes and quotes are locked to your account, and screenshots are stored privately. PDFs are kept at a long, unguessable link: anyone you share a PDF with can open it."),
        Part(heading: "Connected accounts",
             text: "If you connect X or LinkedIn to publish posts, Sangrah stores the access tokens those services give it, and uses them only to post what you ask it to."),
        Part(heading: "What Sangrah doesn't do",
             text: "No ads, no tracking across other apps or websites, and your data is never sold or shared for marketing."),
        Part(heading: "Deleting your data",
             text: "You can delete any save from its \u{22EF} menu. To delete your account and everything in it, email \(SupportContact.email)."),
        Part(heading: "Questions",
             text: "Email \(SupportContact.email). This policy covers the Sangrah beta and was last updated on 30 October 2026.")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CPSpacing.lg) {
                ForEach(parts) { part in
                    VStack(alignment: .leading, spacing: CPSpacing.xs) {
                        Text(part.heading)
                            .font(.cpHeadline)
                            .foregroundColor(.cpText)
                        Text(part.text)
                            .font(.cpBody)
                            .foregroundColor(.cpTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, CPSpacing.screenHorizontal)
            .padding(.vertical, CPSpacing.screenVertical)
        }
        .background(Color.cpBackground)
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
