import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var speech = SpeechManager()
    @StateObject private var notesManager = NotesManager()
    @StateObject private var audioExporter = AudioExporter()
    @State private var textProcessor: TextProcessor? = nil
    @State private var fileName: String = ""
    @State private var errorMessage: String? = nil
    @State private var isLoading = false
    @State private var showVoicePicker = false
    @AppStorage("showRepeatHighlight") private var showRepeatHighlight = false
    @State private var showTOC = false
    @State private var currentFileURL: URL? = nil
    @State private var showNotes = false
    @State private var noteDraft: NoteDraft? = nil
    @State private var textProxy = TextViewProxy()
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
                        isDark: isDark,
                        noteRanges: notesManager.notes.map(\.range),
                        onAddNote: { range, isRevision in
                            beginNote(kind: isRevision ? .revision : .comment, range: range)
                        },
                        proxy: textProxy
                    )
                    .background(Color(nsColor: Theme.background(isDark)))

                    // ── Notes sidebar ───────────────────────────────────────
                    if showNotes, textProcessor != nil {
                        Divider().background(isDark ? Color(white: 0.20) : Color(white: 0.70))
                        NotesPanel(
                            notes:    notesManager.notes,
                            isDark:   isDark,
                            onSelect: { note in
                                speech.jumpTo(charPosition: note.location)
                                textProxy.scroll(to: note.range)
                            },
                            onEdit:   { note in
                                noteDraft = NoteDraft(existing: note, kind: note.kind,
                                                      range: note.range, quote: note.quote,
                                                      content: note.content)
                            },
                            onDelete: { note in notesManager.delete(note, undoManager: undoManager) }
                        )
                    }
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
        .onReceive(Self.commandPublisher) { name in
            handleCommand(name)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFileURL)) { note in
            if let url = note.object as? URL { loadFile(url: url) }
        }
        .sheet(item: $noteDraft) { draft in
            NoteEditorSheet(draft: draft) { finished in
                saveNoteDraft(finished)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async { loadFile(url: url) }
            }
            return true
        }
        .onAppear {
            speech.textProcessor = textProcessor
            setupEventMonitors()
        }
        .onChange(of: textProcessor?.fullText) { _ in
            speech.textProcessor = textProcessor
        }
        .onChange(of: speech.currentSentenceIndex) { _ in
            // Remember the reading position so reopening the file resumes here.
            if let url = currentFileURL, speech.currentOffset > 0 || speech.currentWordRange != nil {
                ReadingPosition.save(speech.currentWordRange?.location ?? speech.currentOffset,
                                     for: url)
            }
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
            .help("Table of Contents  ⌘\\")
            .accessibilityLabel("Table of Contents")

            // Notes panel toggle
            Button(action: { showNotes.toggle() }) {
                Image(systemName: "note.text")
                    .font(.system(size: 13))
                    .foregroundColor(
                        showNotes
                            ? Color(nsColor: Theme.noteAccent)
                            : (isDark ? Color(white: 0.55) : Color(white: 0.40))
                    )
            }
            .buttonStyle(.plain)
            .disabled(textProcessor == nil)
            .help("Notes  ⇧⌘N")
            .accessibilityLabel("Notes")

            Divider().frame(height: 22).background(isDark ? Color(white: 0.30) : Color(white: 0.60))

            // Prev chapter / sentence — shortcut declared in Commands (Playback menu)
            Button(action: { speech.prevChapter() }) {
                Image(systemName: "backward.end.fill")
            }
            .buttonStyle(ToolbarButtonStyle(isDark: isDark))
            .disabled(textProcessor == nil)
            .help(textProcessor?.chapters.isEmpty == false ? "Previous Chapter  ⌘←" : "Previous Sentence  ⌘←")
            .accessibilityLabel(textProcessor?.chapters.isEmpty == false ? "Previous Chapter" : "Previous Sentence")

            // Play / Pause
            Button(action: { playPause() }) {
                Image(systemName: speech.isSpeaking && !speech.isPaused
                      ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(speech.isSpeaking && !speech.isPaused
                                     ? Color(nsColor: Theme.wordHighlight)
                                     : (isDark ? .white : Color(white: 0.15)))
            }
            .buttonStyle(.plain)
            .disabled(textProcessor == nil)
            .accessibilityLabel(speech.isSpeaking && !speech.isPaused ? "Pause" : "Play")

            // Next chapter / sentence — shortcut declared in Commands (Playback menu)
            Button(action: { speech.nextChapter() }) {
                Image(systemName: "forward.end.fill")
            }
            .buttonStyle(ToolbarButtonStyle(isDark: isDark))
            .disabled(textProcessor == nil)
            .help(textProcessor?.chapters.isEmpty == false ? "Next Chapter  ⌘→" : "Next Sentence  ⌘→")
            .accessibilityLabel(textProcessor?.chapters.isEmpty == false ? "Next Chapter" : "Next Sentence")

            Divider().frame(height: 22).background(isDark ? Color(white: 0.30) : Color(white: 0.60))

            // Speed
            HStack(spacing: 6) {
                Button(action: {
                    speech.speechRate = max(0.5, speech.speechRate - 0.1)
                    if speech.isSpeaking { speech.play(from: speech.currentWordRange?.location ?? speech.currentOffset) }
                }) {
                    Image(systemName: "tortoise.fill")
                        .foregroundColor(isDark ? Color(white: 0.55) : Color(white: 0.40))
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Slower  [")
                .accessibilityLabel("Slower")

                Slider(value: $speech.speechRate, in: 0.5...1.5) { editing in
                    if !editing, speech.isSpeaking {
                        let offset = speech.currentWordRange?.location ?? 0
                        speech.play(from: offset)
                    }
                }
                .frame(width: 90)
                .tint(Color(nsColor: Theme.wordHighlight))
                .accessibilityLabel("Playback Speed")

                Button(action: {
                    speech.speechRate = min(1.5, speech.speechRate + 0.1)
                    if speech.isSpeaking { speech.play(from: speech.currentWordRange?.location ?? speech.currentOffset) }
                }) {
                    Image(systemName: "hare.fill")
                        .foregroundColor(isDark ? Color(white: 0.55) : Color(white: 0.40))
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Faster  ]")
                .accessibilityLabel("Faster")
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
            .accessibilityLabel(showRepeatHighlight ? "Repeated Words On" : "Repeated Words Off")

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
            .accessibilityLabel("Voice")

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
            .help("Storyteller Help")
            .accessibilityLabel("Help")
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack {
            Text(fileName.isEmpty ? "No file loaded" : fileName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isDark ? Color(white: 0.55) : Color(white: 0.40))

            if let info = currentChapterInfo() {
                Text("·")
                    .foregroundColor(isDark ? Color(white: 0.30) : Color(white: 0.50))
                Text(info)
                    .font(.system(size: 12))
                    .foregroundColor(isDark ? Color(white: 0.45) : Color(white: 0.35))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            if audioExporter.isExporting {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Exporting audio\u{2026}")
                        .font(.system(size: 12))
                        .foregroundColor(isDark ? Color(white: 0.55) : Color(white: 0.40))
                    Button(action: { audioExporter.cancel() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(isDark ? Color(white: 0.55) : Color(white: 0.40))
                    }
                    .buttonStyle(.plain)
                    .help("Cancel Export")
                    .accessibilityLabel("Cancel Export")
                }
            }

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

    // MARK: - Menu command routing

    /// All payload-free menu/toolbar commands merged into one publisher —
    /// a single onReceive keeps the body light for the type-checker.
    private static let commandPublisher: AnyPublisher<Notification.Name, Never> = {
        let names: [Notification.Name] = [
            .showHelp, .openFileRequested,
            .playPauseRequested, .nextChapterRequested, .prevChapterRequested,
            .speedUpRequested, .speedDownRequested,
            .toggleTOCRequested, .toggleNotesRequested,
            .addCommentRequested, .addRevisionRequested, .exportNotesRequested,
            .findRequested, .findNextRequested, .findPreviousRequested,
            .useSelectionForFindRequested, .exportAudioRequested
        ]
        return Publishers.MergeMany(
            names.map { name in
                NotificationCenter.default.publisher(for: name).map { _ in name }
            }
        )
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }()

    private func handleCommand(_ name: Notification.Name) {
        switch name {
        case .showHelp:             openWindow(id: "help")
        case .openFileRequested:    openFilePicker()
        case .playPauseRequested:   playPause()
        case .nextChapterRequested: speech.nextChapter()
        case .prevChapterRequested: speech.prevChapter()
        case .speedUpRequested:     changeSpeed(by: +0.1)
        case .speedDownRequested:   changeSpeed(by: -0.1)
        case .toggleTOCRequested:   showTOC.toggle()
        case .toggleNotesRequested: showNotes.toggle()
        case .addCommentRequested:  beginNote(kind: .comment, range: nil)
        case .addRevisionRequested: beginNote(kind: .revision, range: nil)
        case .exportNotesRequested: exportNotes()
        case .findRequested:         textProxy.performFind(.showFindInterface)
        case .findNextRequested:     textProxy.performFind(.nextMatch)
        case .findPreviousRequested: textProxy.performFind(.previousMatch)
        case .useSelectionForFindRequested: textProxy.performFind(.setSearchString)
        case .exportAudioRequested: exportAudio()
        default: break
        }
    }

    /// Play/pause with selection awareness: when starting playback while text
    /// is selected (e.g. a ⌘F match), start reading from the selection instead
    /// of resuming the old position. Pausing is unaffected.
    private func playPause() {
        let activelyPlaying = speech.isSpeaking && !speech.isPaused
        if !activelyPlaying, let sel = textProxy.selectedRange() {
            textProxy.collapseSelection()
            speech.jumpTo(charPosition: sel.location, startPlaying: true)
            return
        }
        speech.pauseResume()
    }

    private func changeSpeed(by delta: Float) {
        speech.speechRate = min(1.5, max(0.5, speech.speechRate + delta))
        if speech.isSpeaking {
            speech.play(from: speech.currentWordRange?.location ?? speech.currentOffset)
        }
    }

    // MARK: - Helpers

    private func setupEventMonitors() {
        // Spacebar: play/pause. Can't be a menu shortcut, so we intercept here.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            guard NSApp.keyWindow != nil else { return event }
            // Don't hijack Space while the user is typing (e.g. the note editor).
            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isEditable {
                return event
            }
            if event.keyCode == 49 {
                playPause()
                return nil
            }
            return event
        }
        // Double-click anywhere → zoom/minimise per "AppleActionOnDoubleClick" preference.
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard event.clickCount == 2 else { return event }
            let win: NSWindow? = event.window ?? NSApp.keyWindow
            guard let win else { return event }
            let pref = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
            switch pref {
            case "Minimize": win.miniaturize(nil)
            case "None":     break
            default:         win.zoom(nil)
            }
            return event
        }
    }

    // MARK: - Notes

    /// Open the note editor. Anchor priority: explicit range (context menu) →
    /// current selection → sentence being read → whole document.
    private func beginNote(kind: NoteKind, range: NSRange?) {
        guard let tp = textProcessor else { return }
        let ns = tp.fullText as NSString
        var anchor = range ?? textProxy.selectedRange() ?? currentSentenceRange()
                  ?? NSRange(location: 0, length: 0)
        if NSMaxRange(anchor) > ns.length { anchor = NSRange(location: 0, length: 0) }
        let quote = anchor.length > 0 ? ns.substring(with: anchor) : ""
        // Pause while writing — resume manually when done.
        if speech.isSpeaking && !speech.isPaused { speech.pauseResume() }
        showNotes = true
        noteDraft = NoteDraft(existing: nil, kind: kind, range: anchor, quote: quote)
    }

    private func currentSentenceRange() -> NSRange? {
        guard let tp = textProcessor else { return nil }
        let pos = speech.currentWordRange?.location ?? speech.currentOffset
        guard let idx = tp.sentenceIndex(for: pos) else { return nil }
        return tp.sentences[idx].range
    }

    /// The main window's undo manager — note edits register here so
    /// Edit → Undo/Redo work on notes.
    private var undoManager: UndoManager? {
        (NSApp.mainWindow ?? NSApp.keyWindow)?.undoManager
    }

    private func saveNoteDraft(_ draft: NoteDraft) {
        if var existing = draft.existing {
            existing.kind = draft.kind
            existing.content = draft.content
            notesManager.update(existing, undoManager: undoManager)
        } else {
            notesManager.add(kind: draft.kind, range: draft.range,
                             quote: draft.quote, content: draft.content,
                             undoManager: undoManager)
        }
    }

    // MARK: - Audio export

    private func exportAudio() {
        guard let tp = textProcessor, !audioExporter.isExporting else { return }

        // Scope: whole document, or just the current chapter when there are chapters.
        var text = tp.fullText
        var suffix = ""
        if let ci = currentChapterIndex, !tp.chapters.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Export as MP3"
            alert.informativeText = "Export the entire document, or just \u{201C}\(tp.chapters[ci].title)\u{201D}?"
            alert.addButton(withTitle: "Entire Document")
            alert.addButton(withTitle: "Current Chapter")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertSecondButtonReturn:
                let ns = tp.fullText as NSString
                let start = tp.chapters[ci].charOffset
                let end = ci + 1 < tp.chapters.count ? tp.chapters[ci + 1].charOffset : ns.length
                text = ns.substring(with: NSRange(location: start, length: end - start))
                suffix = " — " + tp.chapters[ci].title
            case .alertThirdButtonReturn:
                return
            default:
                break
            }
        }

        let useMP3 = AudioExporter.mp3EncoderAvailable
        let ext = useMP3 ? "mp3" : "m4a"
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .audio]
        panel.nameFieldStringValue =
            (fileName as NSString).deletingPathExtension + suffix + "." + ext
        if !useMP3 {
            panel.message = "No MP3 encoder found (install lame or ffmpeg via Homebrew) — exporting AAC (.m4a) instead."
        }
        guard panel.runModal() == .OK, let dest = panel.url else { return }

        if speech.isSpeaking && !speech.isPaused { speech.pauseResume() }
        audioExporter.export(text: text,
                             voice: speech.selectedVoiceName,
                             rate: speech.speechRate,
                             to: dest) { result in
            switch result {
            case .success(let url):
                let done = NSAlert()
                done.messageText = "Export Complete"
                done.informativeText = "Saved to \(url.lastPathComponent)."
                done.addButton(withTitle: "Show in Finder")
                done.addButton(withTitle: "OK")
                if done.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            case .failure(let error):
                // Cancellation is user-initiated — no alert needed.
                if case AudioExporter.ExportError.cancelled = error { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func exportNotes() {
        guard !notesManager.notes.isEmpty else {
            errorMessage = "There are no notes to export."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue =
            (fileName as NSString).deletingPathExtension + " Notes.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let md = notesManager.exportMarkdown(documentName: fileName)
        do {
            try md.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Could not export notes: \(error.localizedDescription)"
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.plainText, .pdf,
                               UTType(filenameExtension: "rtf")  ?? .init(exportedAs: "public.rtf"),
                               UTType(filenameExtension: "rtfd") ?? .init(exportedAs: "com.apple.rtfd")]
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
        currentFileURL = url
        RecentFilesManager.shared.add(url)
        // Window title + proxy icon — shows in Mission Control, Exposé, and title bar
        NSApp.keyWindow?.title = url.deletingPathExtension().lastPathComponent
        NSApp.keyWindow?.representedURL = url

        Task {
            do {
                let doc = try await DocumentLoader.load(url: url)
                await MainActor.run {
                    let tp = TextProcessor(text: doc.text, chapters: doc.chapters)
                    self.textProcessor = tp
                    speech.textProcessor = tp
                    notesManager.load(for: url, text: doc.text)
                    // Auto-show TOC if the document has chapters,
                    // and the notes panel if the document has notes.
                    if !tp.chapters.isEmpty { showTOC = true }
                    showNotes = !notesManager.notes.isEmpty
                    AppState.shared.documentLoaded = true
                    AppState.shared.hasChapters = !tp.chapters.isEmpty
                    isLoading = false
                    // Resume where the user left off last time.
                    let length = (doc.text as NSString).length
                    if let saved = ReadingPosition.load(for: url), saved < length {
                        speech.jumpTo(charPosition: saved)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            textProxy.scroll(to: NSRange(location: saved, length: 0))
                        }
                    }
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

    /// "Chapter Three — word 512 of 2,341 · 13 min · 10 min left"
    private func currentChapterInfo() -> String? {
        guard let tp = textProcessor,
              let ci = currentChapterIndex,
              ci < tp.chapterWordCounts.count else { return nil }
        let total = tp.chapterWordCounts[ci]
        guard total > 0 else { return nil }
        let pos = speech.currentWordRange?.location ?? speech.currentOffset
        let startIdx = tp.firstTokenIndex(atOrAfter: tp.chapters[ci].charOffset)
        let cur = min(max(tp.firstTokenIndex(atOrAfter: pos) - startIdx + 1, 1), total)
        let title = tp.chapters[ci].title
        return "\(title) — word \(cur.formatted()) of \(total.formatted())"
             + " · \(readingTimeString(words: total))"
             + " · \(readingTimeString(words: total - cur)) left"
    }

    /// Estimated listening time at the current speech rate (~180 wpm at 1.0×).
    private func readingTimeString(words: Int) -> String {
        let wpm = 180.0 * Double(speech.speechRate)
        let minutes = Double(words) / max(wpm, 1)
        if minutes < 1 { return "under 1 min" }
        let total = Int(minutes.rounded())
        if total < 60 { return "\(total) min" }
        return "\(total / 60) hr \(total % 60) min"
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
