import AVFoundation
import SwiftUI

/// Profile > Listening Voice: the English and Hindi voices on this iPhone,
/// grouped by accent, best quality first. Tapping one picks it and plays a sample.
struct VoicePickerView: View {
    @ObservedObject private var speech = SpeechService.shared
    @State private var voices: [AVSpeechSynthesisVoice] = []

    /// Hindi apart from English; English by accent, Australia first (the default)
    private var groups: [(title: String, voices: [AVSpeechSynthesisVoice])] {
        let byLanguage = Dictionary(grouping: voices, by: \.language)
        let order = ["en-AU", "en-GB", "en-US", "en-IN", "en-IE", "en-ZA", "en-NZ"]
        let languages = byLanguage.keys.sorted { a, b in
            let ia = a.hasPrefix("hi") ? 100 : (order.firstIndex(of: a) ?? 50)
            let ib = b.hasPrefix("hi") ? 100 : (order.firstIndex(of: b) ?? 50)
            return ia != ib ? ia < ib : a < b
        }
        return languages.map { language in
            let sorted = (byLanguage[language] ?? []).sorted { a, b in
                a.quality.rawValue != b.quality.rawValue ? a.quality.rawValue > b.quality.rawValue : a.name < b.name
            }
            return (Self.title(for: language), sorted)
        }
    }

    private var selectedID: String? {
        speech.voiceIdentifier ?? speech.currentVoice()?.identifier
    }

    var body: some View {
        List {
            // Premium voices aren't on an iPhone until the reader downloads them
            if !voices.contains(where: { $0.name == SpeechService.defaultVoiceName && $0.quality == .premium }) {
                Section {
                    Label {
                        Text("For the most natural voice, download **Lee (Premium)**, free: Settings \u{2192} Accessibility \u{2192} Spoken Content \u{2192} Voices \u{2192} English \u{2192} Lee. Sangrah switches to it on its own.")
                            .font(.cpSubhead)
                    } icon: {
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(.cpTint)
                    }
                }
            }

            Section {
                Picker("Speed", selection: $speech.speed) {
                    ForEach(SpeechService.speeds, id: \.self) { speed in
                        Text(SpeedMenu.label(speed)).tag(speed)
                    }
                }
            }

            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.voices, id: \.identifier) { voice in
                        Button {
                            speech.voiceIdentifier = voice.identifier
                            speech.preview(voice)
                        } label: {
                            HStack {
                                Text(voice.name)
                                    .foregroundColor(.cpText)
                                if let badge = Self.badge(for: voice) {
                                    Text(badge)
                                        .font(.cpCaption2.weight(.semibold))
                                        .foregroundColor(.cpTint)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.cpTint.opacity(0.12), in: Capsule())
                                }
                                Spacer()
                                if voice.identifier == selectedID {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.cpTint)
                                }
                            }
                        }
                    }
                }
            }

            Section {
                EmptyView()
            } footer: {
                Text("For the most natural sound, download Premium voices on your iPhone: Settings \u{2192} Accessibility \u{2192} Spoken Content \u{2192} Voices \u{2192} English. They're free, and Sangrah uses them as soon as they're installed. Listening works offline and nothing leaves your phone.")
            }
        }
        .navigationTitle("Listening Voice")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { voices = SpeechService.installedVoices() }
    }

    private static func title(for language: String) -> String {
        if language.hasPrefix("hi") { return "Hindi" }
        let region = Locale(identifier: language).region?.identifier ?? ""
        let name = Locale.current.localizedString(forRegionCode: region) ?? language
        return "English (\(name))"
    }

    private static func badge(for voice: AVSpeechSynthesisVoice) -> String? {
        switch voice.quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return nil
        }
    }
}
