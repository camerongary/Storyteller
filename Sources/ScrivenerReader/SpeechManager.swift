import AppKit
import Combine
import MediaPlayer

class SpeechManager: NSObject, ObservableObject, NSSpeechSynthesizerDelegate {
    private let synthesizer = NSSpeechSynthesizer()

    @Published var isPaused = false
    @Published var isSpeaking = false
    @Published var currentWordRange: NSRange? = nil
    @Published var currentSentenceIndex: Int? = nil
    @Published var speechRate: Float = 0.9          // multiplier of system default
    @Published var selectedVoiceName: NSSpeechSynthesizer.VoiceName? = nil

    var textProcessor: TextProcessor?
    var onWordChange: ((NSRange) -> Void)?
    var onFinished: (() -> Void)?

    @Published var currentOffset: Int = 0
    private var isJumping = false

    /// Absolute char offset where the current utterance ends. The synthesizer
    /// preprocesses whatever it's handed, so speaking the whole remaining
    /// document caused multi-second stalls on every jump. Instead we speak
    /// ~20k-char chunks (cut at sentence boundaries) and chain them.
    private var chunkEnd: Int = 0
    private let maxChunkLength = 20_000

    override init() {
        super.init()
        synthesizer.delegate = self
        // Default to best available voice: Ava Premium → Ava Enhanced → Ava → first in list
        let preferred = ["com.apple.voice.premium.en-US.Ava",
                         "com.apple.voice.enhanced.en-US.Ava",
                         "com.apple.voice.compact.en-US.Ava"]
        selectedVoiceName = preferred
            .compactMap { NSSpeechSynthesizer.VoiceName(rawValue: $0) }
            .first { SpeechManager.availableVoices.contains($0) }
            ?? SpeechManager.readingVoiceNames().first
            ?? NSSpeechSynthesizer.defaultVoice
        setupMediaKeys()
    }

    // All available voice names (for existence checks)
    private static var availableVoices: Set<NSSpeechSynthesizer.VoiceName> {
        Set(NSSpeechSynthesizer.availableVoices)
    }

    // MARK: - Playback

    func play(from charOffset: Int = 0) {
        guard let tp = textProcessor else { return }
        stopInternal()
        currentOffset = charOffset
        let ns = tp.fullText as NSString
        guard charOffset < ns.length else { return }
        chunkEnd = chunkBoundary(after: charOffset, in: tp)
        let slice = ns.substring(with: NSRange(location: charOffset,
                                               length: chunkEnd - charOffset))
        guard !slice.isEmpty else { return }

        applyVoiceAndRate()
        synthesizer.startSpeaking(slice)
        isSpeaking = true
        isPaused = false
        updateNowPlayingState()
    }

    /// End of the chunk starting at `offset`: at most maxChunkLength chars,
    /// extended to the end of the sentence it lands in.
    private func chunkBoundary(after offset: Int, in tp: TextProcessor) -> Int {
        let length = (tp.fullText as NSString).length
        let target = min(offset + maxChunkLength, length)
        if target >= length { return length }
        if let idx = tp.sentenceIndex(for: target) {
            return min(NSMaxRange(tp.sentences[idx].range), length)
        }
        return target
    }

    func pauseResume() {
        if isPaused {
            synthesizer.continueSpeaking()
            isPaused = false
        } else if isSpeaking {
            synthesizer.pauseSpeaking(at: .wordBoundary)
            isPaused = true
        } else {
            play(from: currentOffset)
            return   // play() already calls updateNowPlayingState
        }
        updateNowPlayingState()
    }

    func stop() {
        stopInternal()
        currentWordRange = nil
        currentSentenceIndex = nil
        updateNowPlayingState()
    }

    /// Jump to a character position.
    /// - Parameter startPlaying: if true, always begin playback after jumping
    ///   (even if not currently speaking). Default false preserves existing behaviour.
    func jumpTo(charPosition: Int, startPlaying: Bool = false) {
        let wasSpeaking = isSpeaking && !isPaused
        isJumping = true
        stopInternal()
        currentOffset = charPosition
        currentWordRange = nil
        currentSentenceIndex = textProcessor?.sentenceIndex(for: charPosition)
        if wasSpeaking || startPlaying { play(from: charPosition) }
        // Defer the isJumping reset so that any "didFinishSpeaking" callbacks
        // queued by the stop above still see isJumping = true when they execute,
        // preventing them from clobbering isSpeaking after play() set it to true.
        DispatchQueue.main.async { [weak self] in self?.isJumping = false }
    }

    func nextSentence() {
        guard let tp = textProcessor else { return }
        let pos = currentWordRange?.location ?? currentOffset
        guard let idx = tp.sentenceIndex(for: pos), idx + 1 < tp.sentences.count else { return }
        jumpTo(charPosition: tp.sentences[idx + 1].range.location)
    }

    func prevSentence() {
        guard let tp = textProcessor else { return }
        let pos = currentWordRange?.location ?? currentOffset
        guard let idx = tp.sentenceIndex(for: pos) else { return }
        let target = idx > 0 ? tp.sentences[idx - 1].range.location : 0
        jumpTo(charPosition: target)
    }

    /// Advance to the next chapter when chapters are available;
    /// otherwise advance one sentence (existing behaviour).
    func nextChapter() {
        guard let tp = textProcessor, !tp.chapters.isEmpty else {
            nextSentence(); return
        }
        let pos = currentWordRange?.location ?? currentOffset
        guard let idx = tp.chapterIndex(for: pos) else {
            // Before the first chapter — jump to it
            jumpTo(charPosition: tp.chapters[0].charOffset); return
        }
        guard idx + 1 < tp.chapters.count else { return }
        jumpTo(charPosition: tp.chapters[idx + 1].charOffset)
    }

    /// Go back to the previous chapter when chapters are available;
    /// otherwise go back one sentence (existing behaviour).
    func prevChapter() {
        guard let tp = textProcessor, !tp.chapters.isEmpty else {
            prevSentence(); return
        }
        let pos = currentWordRange?.location ?? currentOffset
        guard let idx = tp.chapterIndex(for: pos) else { return }
        let target = idx > 0 ? tp.chapters[idx - 1].charOffset : tp.chapters[0].charOffset
        jumpTo(charPosition: target)
    }

    private func stopInternal() {
        synthesizer.stopSpeaking(at: .immediateBoundary)
        isSpeaking = false
        isPaused = false
    }

    private func applyVoiceAndRate() {
        if let voice = selectedVoiceName {
            synthesizer.setVoice(voice)
        }
        // NSSpeechSynthesizer rate is words-per-minute; default ~180 wpm
        synthesizer.rate = 180.0 * speechRate  // 180 wpm is the typical default
    }

    // MARK: - NSSpeechSynthesizerDelegate

    func speechSynthesizer(_ sender: NSSpeechSynthesizer,
                           willSpeakWord characterRange: NSRange,
                           of string: String) {
        let actual = NSRange(location: characterRange.location + currentOffset,
                             length: characterRange.length)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.currentWordRange = actual
            self.currentSentenceIndex = self.textProcessor?.sentenceIndex(for: actual.location)
            self.onWordChange?(actual)
        }
    }

    func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        // Outer guard: fast-exit for synchronous calls during a jump.
        guard !isJumping else { return }
        DispatchQueue.main.async { [weak self] in
            // Inner guard: re-check at execution time in case the reset was deferred.
            guard let self, !self.isJumping else { return }
            // Chunk finished but the document hasn't — continue seamlessly.
            let textLength = (self.textProcessor?.fullText as NSString?)?.length ?? 0
            if finishedSpeaking, self.chunkEnd < textLength {
                self.isJumping = true   // shield flags from the restart's stop callbacks
                self.play(from: self.chunkEnd)
                DispatchQueue.main.async { [weak self] in self?.isJumping = false }
                return
            }
            self.isSpeaking = false
            self.isPaused = false
            self.currentWordRange = nil
            if finishedSpeaking { self.onFinished?() }
        }
    }

    // MARK: - Media key / Remote Command Centre

    /// Register with MPRemoteCommandCenter so the keyboard ▶︎/⏸ key (and
    /// Control Centre) controls Storyteller even when it is in the background,
    /// preventing the system from routing those events to Apple Music.
    private func setupMediaKeys() {
        let cc = MPRemoteCommandCenter.shared()

        cc.togglePlayPauseCommand.isEnabled = true
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.pauseResume(); return .success
        }
        cc.playCommand.isEnabled = true
        cc.playCommand.addTarget { [weak self] _ in
            self?.pauseResume(); return .success
        }
        cc.pauseCommand.isEnabled = true
        cc.pauseCommand.addTarget { [weak self] _ in
            self?.pauseResume(); return .success
        }

        // ⏭ / ⏮ hardware keys → chapter (or sentence) navigation
        cc.nextTrackCommand.isEnabled = true
        cc.nextTrackCommand.addTarget { [weak self] _ in
            self?.nextChapter(); return .success
        }
        cc.previousTrackCommand.isEnabled = true
        cc.previousTrackCommand.addTarget { [weak self] _ in
            self?.prevChapter(); return .success
        }

        cc.seekForwardCommand.isEnabled    = false
        cc.seekBackwardCommand.isEnabled   = false
        cc.changePlaybackPositionCommand.isEnabled = false

        // Seed nowPlayingInfo — this is what causes macOS to treat
        // Storyteller as the active audio app for media-key routing.
        updateNowPlayingState()
    }

    /// Keep the system's Now Playing metadata in sync with playback state.
    /// Call this whenever isSpeaking or isPaused changes.
    func updateNowPlayingState() {
        let title = textProcessor.flatMap { tp -> String? in
            // Use the current chapter title if available
            let pos = currentWordRange?.location ?? currentOffset
            if let idx = tp.chapterIndex(for: pos) {
                return tp.chapters[idx].title
            }
            return nil
        } ?? "Storyteller"

        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle:      title,
            MPMediaItemPropertyArtist:     "Storyteller",
            MPNowPlayingInfoPropertyMediaType:
                NSNumber(value: MPNowPlayingInfoMediaType.audio.rawValue),
        ]

        MPNowPlayingInfoCenter.default().playbackState =
            isSpeaking && !isPaused ? .playing : .paused
    }

    // MARK: - Voice helpers

    private static let noveltyVoices: Set<String> = [
        "Agnes","Albert","Bad News","Bahh","Bells","Boing","Bruce","Bubbles",
        "Cellos","Fred","Good News","Jester","Junior","Kathy","Organ","Ralph",
        "Superstar","Trinoids","Whisper","Wobble","Zarvox","Aman","Tara","Rishi"
    ]

    private static func voiceRank(_ id: String) -> Int {
        if id.contains(".premium.")  || id.contains("premium")  { return 0 }
        if id.contains(".enhanced.") || id.contains("enhanced") { return 1 }
        return 2
    }

    /// English-only voices used as the fallback default in init().
    /// Deduplicates multi-locale voices (keeps en-US), sorts Premium → Enhanced → Standard.
    static func readingVoiceNames() -> [NSSpeechSynthesizer.VoiceName] {
        var seen = Set<String>()
        return NSSpeechSynthesizer.availableVoices
            .compactMap { voice -> (NSSpeechSynthesizer.VoiceName, String, Int)? in
                let attrs  = NSSpeechSynthesizer.attributes(forVoice: voice)
                let locale = attrs[.localeIdentifier] as? String ?? ""
                let name   = attrs[.name] as? String ?? ""
                guard locale.lowercased().hasPrefix("en"),
                      !noveltyVoices.contains(name) else { return nil }
                return (voice, name, voiceRank(voice.rawValue))
            }
            .sorted { a, b in a.2 == b.2 ? a.1 < b.1 : a.2 < b.2 }
            .compactMap { item -> NSSpeechSynthesizer.VoiceName? in
                let baseName = item.1
                    .replacingOccurrences(of: " \\(.*\\)$", with: "", options: .regularExpression)
                let key = "\(baseName)|\(item.2)"
                if seen.contains(key) { return nil }
                seen.insert(key)
                return item.0
            }
    }

    /// All installed voices grouped by language, English first.
    /// Within each language: Premium → Enhanced → Standard, then alphabetical.
    /// Novelty/joke voices are excluded; multi-locale duplicates are collapsed.
    static func groupedVoiceNames() -> [(language: String, voices: [NSSpeechSynthesizer.VoiceName])] {
        // Collect every non-novelty voice with its attributes
        let all: [(voice: NSSpeechSynthesizer.VoiceName, name: String, lang: String, rank: Int)] =
            NSSpeechSynthesizer.availableVoices.compactMap { voice in
                let attrs  = NSSpeechSynthesizer.attributes(forVoice: voice)
                let locale = attrs[.localeIdentifier] as? String ?? ""
                let name   = attrs[.name] as? String ?? ""
                guard !noveltyVoices.contains(name) else { return nil }
                let lang = locale.components(separatedBy: "-").first ?? locale
                return (voice, name, lang, voiceRank(voice.rawValue))
            }
            .sorted { a, b in
                if a.lang != b.lang { return a.lang < b.lang }
                return a.rank == b.rank ? a.name < b.name : a.rank < b.rank
            }

        // Group by language code; deduplicate within each group
        var voicesByLang: [String: [NSSpeechSynthesizer.VoiceName]] = [:]
        var seenPerLang:  [String: Set<String>] = [:]

        for item in all {
            let baseName = item.name
                .replacingOccurrences(of: " \\(.*\\)$", with: "", options: .regularExpression)
            let key = "\(baseName)|\(item.rank)"
            if seenPerLang[item.lang, default: []].contains(key) { continue }
            seenPerLang[item.lang, default: []].insert(key)
            voicesByLang[item.lang, default: []].append(item.voice)
        }

        // Build result: English first, then alphabetical by display name
        let langDisplayName: (String) -> String = { code in
            Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
        }
        return voicesByLang
            .map { (language: langDisplayName($0.key), voices: $0.value) }
            .sorted { a, b in
                let aEn = a.language.lowercased() == "english"
                let bEn = b.language.lowercased() == "english"
                if aEn != bEn { return aEn }
                return a.language < b.language
            }
    }

    static func displayName(for voice: NSSpeechSynthesizer.VoiceName) -> String {
        let raw = NSSpeechSynthesizer.attributes(forVoice: voice)[.name] as? String
               ?? voice.rawValue.components(separatedBy: ".").last ?? voice.rawValue
        // Strip locale suffixes like " (English (US))", " (French (France))", etc.
        return raw.replacingOccurrences(of: " \\([^)]+\\(.*?\\)\\)$", with: "",
                                        options: .regularExpression)
    }
}
