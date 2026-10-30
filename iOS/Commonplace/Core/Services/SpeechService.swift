import AVFoundation
import MediaPlayer
import NaturalLanguage

/// Reads a save aloud with Apple's on-device voices: free, offline, nothing sent
/// anywhere. The title and author come first, then the article a paragraph at a
/// time, so the player can skip and show progress. Keeps playing with the screen
/// locked (UIBackgroundModes audio) and shows lock-screen controls.
@MainActor
final class SpeechService: NSObject, ObservableObject {
    static let shared = SpeechService()

    /// The save being read; nil when nothing is playing or paused
    @Published private(set) var document: Document?
    @Published private(set) var paragraphs: [String] = []
    @Published private(set) var paragraphIndex = 0
    @Published private(set) var isPlaying = false

    /// Speed as a multiple of normal speech, one of `SpeechService.speeds`
    @Published var speed: Float {
        didSet {
            UserDefaults.standard.set(speed, forKey: Self.speedKey)
            // Restart the current paragraph so the new speed is heard at once
            if isPlaying { speak(paragraphIndex) }
        }
    }

    /// The chosen voice's identifier; nil means the default (Lee, Australian)
    @Published var voiceIdentifier: String? {
        didSet {
            UserDefaults.standard.set(voiceIdentifier, forKey: Self.voiceKey)
            if isPlaying { speak(paragraphIndex) }
        }
    }

    static let speeds: [Float] = [0.8, 1.0, 1.2, 1.5, 1.75, 2.0]
    /// Picked by the owner on 30 Oct 2026 from Apple's Premium voices
    nonisolated static let defaultVoiceName = "Lee"
    nonisolated static let defaultVoiceLanguage = "en-AU"
    private static let speedKey = "listenSpeed"
    private static let voiceKey = "listenVoiceIdentifier"

    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    private var language = "en"

    private override init() {
        let savedSpeed = UserDefaults.standard.float(forKey: Self.speedKey)
        speed = Self.speeds.contains(savedSpeed) ? savedSpeed : 1.0
        voiceIdentifier = UserDefaults.standard.string(forKey: Self.voiceKey)
        super.init()
        synthesizer.delegate = self
        setUpRemoteCommands()
        NotificationCenter.default.addObserver(
            self, selector: #selector(audioInterrupted(_:)),
            name: AVAudioSession.interruptionNotification, object: nil
        )
    }

    // MARK: - Playback

    func isCurrent(_ document: Document) -> Bool { self.document?.id == document.id }

    /// Starts reading `document` from the top, or pauses and resumes it if it's the one playing
    func toggle(_ document: Document) {
        if isCurrent(document) {
            isPlaying ? pause() : resume()
            return
        }
        let parts = Self.paragraphs(for: document)
        guard !parts.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        self.document = document
        paragraphs = parts
        language = Self.language(of: document)
        activateAudioSession()
        speak(0)
    }

    func pause() {
        guard isPlaying else { return }
        synthesizer.pauseSpeaking(at: .word)
        isPlaying = false
        updateNowPlaying()
    }

    func resume() {
        guard document != nil, !isPlaying else { return }
        activateAudioSession()
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
            isPlaying = true
            updateNowPlaying()
        } else {
            speak(paragraphIndex)
        }
    }

    func skipForward() {
        guard paragraphIndex + 1 < paragraphs.count else { return }
        speak(paragraphIndex + 1)
    }

    func skipBack() {
        speak(max(paragraphIndex - 1, 0))
    }

    func stop() {
        currentUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        document = nil
        paragraphs = []
        paragraphIndex = 0
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Reads one sentence in a voice so the picker can preview it
    func preview(_ voice: AVSpeechSynthesisVoice) {
        if isPlaying { pause() }
        activateAudioSession()
        let utterance = AVSpeechUtterance(string: voice.language.hasPrefix("hi")
            ? "नमस्ते, मैं संग्रह से आपके लेख पढ़ूँगी।"
            : "Hello, I'll read your saved articles to you in Sangrah.")
        utterance.voice = voice
        utterance.rate = Self.utteranceRate(for: speed)
        currentUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }

    /// Minutes left at the current speed
    var minutesLeft: Int {
        Self.minutes(for: Array(paragraphs.dropFirst(paragraphIndex)), speed: speed)
    }

    /// Listening time for a whole save, counted from the words that will be read
    nonisolated static func listeningMinutes(for document: Document, speed: Float) -> Int {
        minutes(for: paragraphs(for: document), speed: speed)
    }

    /// About 160 spoken words a minute at 1×
    nonisolated static func minutes(for paragraphs: [String], speed: Float) -> Int {
        let words = paragraphs.reduce(0) { $0 + $1.split(separator: " ").count }
        return max(1, Int((Double(words) / (160 * Double(speed))).rounded(.up)))
    }

    private func speak(_ index: Int) {
        guard paragraphs.indices.contains(index) else { return }
        let utterance = AVSpeechUtterance(string: paragraphs[index])
        utterance.voice = currentVoice()
        utterance.rate = Self.utteranceRate(for: speed)
        utterance.postUtteranceDelay = 0.3
        currentUtterance = utterance
        paragraphIndex = index
        // Cancelling the old paragraph reports didCancel, not didFinish, so it can't advance
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
        isPlaying = true
        updateNowPlaying()
    }

    private func finished(_ utterance: AVSpeechUtterance) {
        guard utterance === currentUtterance else { return }
        if paragraphIndex + 1 < paragraphs.count {
            speak(paragraphIndex + 1)
        } else {
            stop()
        }
    }

    // MARK: - Voices

    func currentVoice() -> AVSpeechSynthesisVoice? {
        let options = Self.installedVoices().map(VoiceOption.init)
        guard let chosen = Self.preferredVoice(language: language, among: options, saved: voiceIdentifier) else {
            return AVSpeechSynthesisVoice(language: language == "hi" ? "hi-IN" : Self.defaultVoiceLanguage)
        }
        return AVSpeechSynthesisVoice(identifier: chosen.id)
    }

    /// English and Hindi voices installed on this device, without novelty and personal voices
    static func installedVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { voice in
            (voice.language.hasPrefix("en") || voice.language.hasPrefix("hi"))
                && !voice.voiceTraits.contains(.isNoveltyVoice)
                && !voice.voiceTraits.contains(.isPersonalVoice)
        }
    }

    /// A voice reduced to what the choice depends on, so the rule can be tested without the device's voices
    struct VoiceOption: Identifiable, Hashable {
        let id: String
        let name: String
        let language: String
        /// 3 premium, 2 enhanced, 1 default
        let quality: Int

        init(id: String, name: String, language: String, quality: Int) {
            self.id = id
            self.name = name
            self.language = language
            self.quality = quality
        }

        init(_ voice: AVSpeechSynthesisVoice) {
            let quality: Int
            switch voice.quality {
            case .premium: quality = 3
            case .enhanced: quality = 2
            default: quality = 1
            }
            self.init(id: voice.identifier, name: voice.name, language: voice.language, quality: quality)
        }
    }

    /// The reader's own pick when it suits the article's language; otherwise
    /// Lee (Australian), the best Australian voice, or the best English one.
    /// Hindi articles get the best Hindi voice.
    nonisolated static func preferredVoice(language: String, among voices: [VoiceOption], saved: String?) -> VoiceOption? {
        let family = language == "hi" ? "hi" : "en"
        let suitable = voices.filter { $0.language.hasPrefix(family) }
        if let saved, let pick = suitable.first(where: { $0.id == saved }) { return pick }
        let best = { (pool: [VoiceOption]) in pool.max { ($0.quality, $1.name) < ($1.quality, $0.name) } }
        if family == "en" {
            let australian = suitable.filter { $0.language == defaultVoiceLanguage }
            if let lee = australian.filter({ $0.name == defaultVoiceName }).max(by: { $0.quality < $1.quality }) {
                return lee
            }
            if let bestAustralian = best(australian) { return bestAustralian }
        }
        return best(suitable)
    }

    // MARK: - Text

    /// What gets read: the title, "By author", then the article's paragraphs
    /// without links or list bullets. Falls back to the summary when there's no text.
    nonisolated static func paragraphs(for document: Document) -> [String] {
        var parts = [document.title]
        if let author = (document.authorName ?? document.authorHandle)?.trimmingCharacters(in: .whitespaces), !author.isEmpty {
            parts.append("By \(author.hasPrefix("@") ? String(author.dropFirst()) : author).")
        }
        let body = document.bodyPlain.isEmpty ? (document.aiSummaryShort ?? "") : document.bodyPlain
        // A body that repeats the title or byline as its first lines doesn't say them twice
        let fresh = speakableParagraphs(body).drop { line in
            parts.contains { $0.caseInsensitiveCompare(line) == .orderedSame || "\(line)." == $0 }
        }
        return parts + fresh
    }

    /// Paragraphs (split at blank lines) with links, list bullets and extra spacing
    /// removed; lines with no letters (dividers, bare numbers) are skipped
    nonisolated static func speakableParagraphs(_ body: String) -> [String] {
        body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { paragraph in
                paragraph
                    .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"(?m)^\s*(•|-|\*)\s+"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter { $0.rangeOfCharacter(from: .letters) != nil }
    }

    nonisolated static func language(of document: Document) -> String {
        language(ofText: document.title + " " + document.bodyPlain)
    }

    /// "hi" for Hindi, otherwise "en": the two voice families Listen offers
    nonisolated static func language(ofText text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(1000)))
        return recognizer.dominantLanguage == .hindi ? "hi" : "en"
    }

    /// AVSpeech's rate isn't a multiplier: 0.5 is normal and 1.0 the maximum
    nonisolated static func utteranceRate(for speed: Float) -> Float {
        min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * speed)
    }

    // MARK: - System integration

    private func activateAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    @objc private func audioInterrupted(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
        Task { @MainActor in self.pause() }
    }

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying ? self.pause() : self.resume()
            }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipForward() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipBack() }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let document else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: document.title,
            MPMediaItemPropertyArtist: document.authorName ?? document.sourceDomain ?? "Sangrah",
            MPMediaItemPropertyAlbumTitle: "Sangrah",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        info[MPNowPlayingInfoPropertyChapterNumber] = paragraphIndex
        info[MPNowPlayingInfoPropertyChapterCount] = paragraphs.count
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished(utterance) }
    }
}
