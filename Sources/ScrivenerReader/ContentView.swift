import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var speech = SpeechManager()
    @State private var textProcessor: TextProcessor? = nil
    @State private var fileName: String = ""
    @State private var errorMessage: String? = nil
    @State private var isLoading = false
    @State private var showVoicePicker = false
    @State private var showRepeatHighlight = false
    @State private var showTOC = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    /// Index in the chapter list that contains the current reading position.
    private var currentChapterIndex: Int? {
        guard let tp = textProcessor, !tp.chapters.isEmpty else { return nil }
        let pos = speech.currentWordRange?.location ?? speech.currentOffset
        return tp.chapterIndex(for: pos)
    }

    var body: some View {
        ZStack {
            Color(nsColor: Theme.background(isDark)).ignoresSafeArea()

            VStack(spacing: 0) {
                toolbar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        isDark
                            ? Color(nsColor: NSColor(white: 0.10, alpha: 0.97))
                            : Color(nsColor: NSColor(white: 0.88, alpha: 0.97))
                    )

                Divider().background(isDark ? Color(white: 0.20) : Color(white: 0.70))

                HStack(spacing: 0) {
                    // ── TOC sidebar ─────────────────────────────────────────
                    if showTOC, let tp = textProcessor, !tp.chapters.isEmpty {
                        TOCPanel(
                            chapters:    tp.chapters,
                            activeIndex: currentChapterIndex,
                            isDark:      isDark,
                            onSelect:    { offset in
                                // Navigate to the chapter. If already reading, continue
                                // from there; otherwise just move the position without
                                // starting playback (startPlaying defaults to false).
                                speech.jumpTo(charPosition: offset)
                            }
                        )
                        Divider().background(isDark ? Color(white: 0.20) : Color(white: 0.70))
                    }

                    // ── Main text view ──────────────────────────────────────
                    HighlightedTextView(
                        textProcessor: textProcessor,
                        speech: speech,
                        onWordTapped: { charPos in
                            // Clicking always starts (or resumes) playback from
                            // the tapped position.
                            speech.jumpTo(charPosition: charPos, startPlaying: true)
                        },
                        showRepeatHighlight: showRepeatHighlight,
                        isDark: isDark
                    )
                    .background(Color(nsColor: Theme.background(isDark)))
                }

                Divider().background(isDark ? Color(white: 0.20) : Color(white: 0.70))
                statusBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        isDark
                            ? Color(nsColor: NSColor(white: 0.10, alpha: 0.97))
                            : Color(nsColor: NSColor(white: 0.88, alpha: 0.97))
                    )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showHelp)) { _ in
            openWindow(id: "help")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFileRequested)) { _ in
            openFilePicker()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFileURL)) { note in
            if let url = note.object as? URL {
                loadFile(url: url)
            }
        }
        .onAppear {
            speech.textProcessor = textProcessor
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 49, NSApp.keyWindow != nil { // spacebar
                    speech.pauseResume()
                    return nil
                }
                if event.keyCode == 33, NSApp.keyWindow != nil { // [ = slower
                    speech.speechRate = max(0.5, speech.speechRate - 0.1)
                    return nil
                }
                if event.keyCode == 30, NSApp.keyWindow != nil { // ] = faster
                    speech.speechRate = min(1.5, speech.speechRate + 0.1)
                    return nil
                }
                return event
            }
            // Double-click anywhere in the window → zoom / minimise per system preference.
            // (Equivalent to double-clicking a native title bar.)
            NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
                guard event.clickCount == 2 else { return event }
                guard let window = event.window ?? NSApp.keyWindow else { return event }
                let pref = UserDefaults.standard
                    .string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
                switch pref {
                case "Minimize": window.miniaturize(nil)
                case "None":     break
                default:         window.zoom(nil)
                }
                return event
            }
        }
        .onChange(of: textProcessor?.fullText) { _ in
            speech.textProcessor = textProcessor
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 14) {
            // Open
            Button(action: openFilePicker) {
                Label("Open", systemImage: "folder.badge.plus")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(ToolbarButtonStyle(isDark: isDark))

            Divider().frame(height: 22).background(isDark ? Color(white: 0.30) : Color(white: 0.60))

            // TOC toggle
            Button(action: { showTOC.toggle() }) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 13))
                    .foregroundColor(
                        showTOC
                            ? Color(nsColor: Theme.repeatedActive(isDark))
                            : (isDark ? Color(white: 0.55) : Color(white: 0.40))
                    )
            }
            .buttonStyle(.plain)
            .disabled((textProcessor?.chapters.isEmpty) ?? true)
            .help("Table of Contents")

            Divider().frame(height: 22).background(isDark ? Color(white: 0.30) : Color(white: 0.60))

            // Prev chapter / sentence
            Button(action: { speech.prevChapter() }) {
                Image(systemName: "backward.end.fill")
            }
            .buttonStyle(ToolbarButtonStyle(isDark: isDark))
            .disabled(textProcessor == nil)
            .help(textProcessor?.chapters.isEmpty == false ? "Previous chapter" : "Previous sentence")
            .keyboardShortcut(.leftArrow, modifiers: [.command])

            // Play / Pause
            Button(action: { speech.pauseResume() }) {
                Image(systemName: speech.isSpeaking && !speech.isPaused
                      ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(speech.isSpeaking && !speech.isPaused
                                     ? Color(nsColor: Theme.wordHighlight)
                                     : (isDark ? .white : Color(white: 0.15)))
            }
            .buttonStyle(.plain)
            .disabled(textProcessor == nil)

            // Next chapter / sentence
            Button(action: { speech.nextChapter() }) {
                Image(systemName: "forward.end.fill")
            }
            .buttonStyle(ToolbarButtonStyle(isDark: isDark))
            .disabled(textProcessor == nil)
            .help(textProcessor?.chapters.isEmpty == false ? "Next chapter" : "Next sentence")
            .keyboardShortcut(.rightArrow, modifiers: [.command])

            Divider().frame(height: 22).background(isDark ? Color(white: 0.30) : Color(white: 0.60))

            // Speed
            HStack(spacing: 6) {
                Button(action: {
                    speech.speechRate = max(0.5, speech.speechRate - 0.1)
                }) {
                    Image(systemName: "tortoise.fill")
                        .foregroundColor(isDark ? Color(white: 0.55) : Color(white: 0.40))
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)

                Slider(value: $speech.speechRate, in: 0.5...1.5) { editing in
                    if !editing, speech.isSpeaking {
                        let offset = speech.currentWordRange?.location ?? 0
                        speech.play(from: offset)
                    }
                }
                .frame(width: 90)
                .tint(Color(nsColor: Theme.wordHighlight))

                Button(action: {
                    speech.speechRate = min(1.5, speech.speechRate + 0.1)
                }) {
                    Image(systemName: "hare.fill")
                        .foregroundColor(isDark ? Color(white: 0.55) : Color(white: 0.40))
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }

            Divider().frame(height: 22).background(isDark ? Color(white: 0.30) : Color(white: 0.60))

            // Repeat highlight toggle
            Button(action: { showRepeatHighlight.toggle() }) {
                Image(systemName: "repeat")
                    .foregroundColor(showRepeatHighlight
                        ? Color(nsColor: Theme.repeatedActive(isDark))
                        : (isDark ? Color(white: 0.40) : Color(white: 0.55)))
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .help("Toggle repeated-word highlighting")

            Divider().frame(height: 22).background(isDark ? Color(white: 0.30) : Color(white: 0.60))

            // Voice picker
            Menu {
                ForEach(SpeechManager.groupedVoiceNames(), id: \.language) { group in
                    Section(group.language) {
                        ForEach(group.voices, id: \.rawValue) { voice in
                            Button(action: {
                                speech.selectedVoiceName = voice
                                if speech.isSpeaking {
                                    let offset = speech.currentWordRange?.location ?? 0
                                    speech.play(from: offset)
                                }
                            }) {
                                HStack {
                                    if speech.selectedVoiceName == voice {
                                        Image(systemName: "checkmark")
                                    }
                                    Text(voiceDisplayName(voice))
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                    Text(speech.selectedVoiceName.map { voiceDisplayName($0) } ?? "Voice")
                        .font(.system(size: 12))
                }
                .foregroundColor(isDark ? Color(white: 0.80) : Color(white: 0.20))
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: 130)

            Spacer()

            if isLoading {
                ProgressView().controlSize(.small)
            }

            // Help button
            Button(action: { NotificationCenter.default.post(name: .showHelp, object: nil) }) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 15))
                    .foregroundColor(isDark ? Color(white: 0.55) : Color(white: 0.40))
            }
            .buttonStyle(.plain)
            .help("Help")
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack {
            Text(fileName.isEmpty ? "No file loaded" : fileName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isDark ? Color(white: 0.55) : Color(white: 0.40))

            Spacer()

            if let tp = textProcessor {
                let wordCount = tp.wordTokens.count
                let current = currentWordIndex(tp: tp)
                Text("\(current) / \(wordCount) words")
                    .font(.system(size: 12))
                    .foregroundColor(isDark ? Color(white: 0.45) : Color(white: 0.35))

                Text("·")
                    .foregroundColor(isDark ? Color(white: 0.30) : Color(white: 0.50))

                let repeatedCount = tp.repeatedWordLocations.count
                HStack(spacing: 4) {
                    Circle().fill(Color(nsColor: Theme.repeatedActive(isDark))).frame(width: 7, height: 7)
                    Text("\(repeatedCount) repeated")
                        .font(.system(size: 12))
                        .foregroundColor(isDark ? Color(white: 0.45) : Color(white: 0.35))
                }
            }
        }
    }

    // MARK: - Helpers

    private func openFilePicker() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.plainText, .pdf]
        if let epubType = UTType(filenameExtension: "epub") {
            types.append(epubType)
        } else {
            types.append(UTType(exportedAs: "org.idpf.epub-container"))
        }
        panel.allowedContentTypes = types
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Open File"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFile(url: url)
    }

    private func loadFile(url: URL) {
        speech.stop()
        isLoading = true
        fileName = url.lastPathComponent
        showTOC = false
        RecentFilesManager.shared.add(url)

        Task {
            do {
                let doc = try await DocumentLoader.load(url: url)
                await MainActor.run {
                    let tp = TextProcessor(text: doc.text, chapters: doc.chapters)
                    self.textProcessor = tp
                    speech.textProcessor = tp
                    // Auto-show TOC if the document has chapters
                    if !tp.chapters.isEmpty { showTOC = true }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func voiceDisplayName(_ voice: NSSpeechSynthesizer.VoiceName) -> String {
        SpeechManager.displayName(for: voice)
    }

    private func currentWordIndex(tp: TextProcessor) -> Int {
        guard let range = speech.currentWordRange else { return 0 }
        return (tp.wordTokens.firstIndex { $0.range.location == range.location } ?? 0) + 1
    }
}

// MARK: - Button style

struct ToolbarButtonStyle: ButtonStyle {
    var isDark: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(configuration.isPressed
                ? (isDark ? Color(white: 0.60) : Color(white: 0.45))
                : (isDark ? Color(white: 0.82) : Color(white: 0.20)))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

// MARK: - NSColor → SwiftUI

extension NSColor {
    var swiftUIColor: Color { Color(nsColor: self) }
}
