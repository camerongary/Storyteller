import SwiftUI
import AppKit

// MARK: - Theme

enum Theme {
    // Shared colors (same in both modes)
    static let wordHighlight    = NSColor(srgbRed: 0.95, green: 0.85, blue: 0.15, alpha: 0.85)
    static let wordHighlightFg  = NSColor(white: 0.05, alpha: 1)
    static let font             = NSFont(name: "Georgia", size: 19)
                               ?? NSFont.systemFont(ofSize: 19, weight: .regular)
    static let lineHeightMult: CGFloat = 1.45

    // Mode-specific
    static func background(_ isDark: Bool) -> NSColor {
        isDark
            ? NSColor(srgbRed: 0.07, green: 0.07, blue: 0.07, alpha: 1)
            : NSColor(srgbRed: 0.97, green: 0.95, blue: 0.91, alpha: 1)
    }
    static func dimText(_ isDark: Bool) -> NSColor {
        isDark
            ? NSColor(white: 0.28, alpha: 1)
            : NSColor(white: 0.68, alpha: 1)
    }
    static func activeText(_ isDark: Bool) -> NSColor {
        isDark
            ? NSColor(srgbRed: 0.82, green: 0.78, blue: 0.72, alpha: 1)
            : NSColor(white: 0.10, alpha: 1)
    }
    static func sentenceHighlight(_ isDark: Bool) -> NSColor {
        isDark
            ? NSColor(white: 0.13, alpha: 1)
            : NSColor(white: 0.87, alpha: 1)
    }
    static func repeatedDim(_ isDark: Bool) -> NSColor {
        isDark
            ? NSColor(srgbRed: 0.50, green: 0.27, blue: 0.10, alpha: 1)
            : NSColor(srgbRed: 0.75, green: 0.45, blue: 0.20, alpha: 1)
    }
    static func repeatedActive(_ isDark: Bool) -> NSColor {
        isDark
            ? NSColor(srgbRed: 0.90, green: 0.50, blue: 0.20, alpha: 1)
            : NSColor(srgbRed: 0.72, green: 0.30, blue: 0.08, alpha: 1)
    }

    // Legacy accessors used in ContentView status bar (dark mode defaults)
    static let repeatedWord = repeatedActive(true)
}

// MARK: - Clickable NSTextView subclass

final class ClickableTextView: NSTextView {
    var onCharacterTapped: ((Int) -> Void)?
    var onSpacebar: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let charIdx = characterIndexForInsertion(at: point)
        if charIdx < string.count {
            onCharacterTapped?(charIdx)
        }
        // Don't call super — we don't want text selection cursor changing
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 { // spacebar
            onSpacebar?()
        } else {
            super.keyDown(with: event)
        }
    }

    // Suppress right-click context menu
    override func menu(for event: NSEvent) -> NSMenu? { nil }
}

// MARK: - NSViewRepresentable

struct HighlightedTextView: NSViewRepresentable {
    let textProcessor: TextProcessor?
    @ObservedObject var speech: SpeechManager
    var onWordTapped: (Int) -> Void   // char position in fullText
    var showRepeatHighlight: Bool
    var isDark: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = Theme.background(isDark)
        scrollView.scrollerStyle = .overlay

        let textView = ClickableTextView()
        textView.isEditable = false
        textView.isSelectable = false
        textView.isRichText = false
        textView.backgroundColor = Theme.background(isDark)
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 80, height: 60)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                        height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        // Allow the layout manager to lay out only the visible range rather than
        // all text up to the target position. Without this, jumping to a position
        // deep in a large document forces O(n) layout of all preceding text.
        textView.layoutManager?.allowsNonContiguousLayout = true

        textView.onCharacterTapped = { [weak textView] charIdx in
            guard let _ = textView else { return }
            onWordTapped(charIdx)
        }
        textView.onSpacebar = {
            context.coordinator.speechRef?()
        }

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        let coord = context.coordinator

        // Wire spacebar action to current speech manager
        coord.speechRef = { [weak speech = speech] in speech?.pauseResume() }

        // Check if theme changed (dark/light mode switch)
        let themeChanged = coord.lastIsDark != isDark

        // Rebuild attributed string if text changed OR theme changed
        let textChanged = coord.loadedText !== textProcessor
        let repeatChanged = coord.lastShowRepeat != showRepeatHighlight

        if textChanged || themeChanged || repeatChanged {
            coord.loadedText = textProcessor
            coord.lastWordRange = nil
            coord.lastSentenceIdx = nil
            coord.lastIsDark = isDark
            coord.lastShowRepeat = showRepeatHighlight

            // Update backgrounds on theme change
            textView.backgroundColor = Theme.background(isDark)
            scrollView.backgroundColor = Theme.background(isDark)

            if let tp = textProcessor {
                let attrStr = buildBaseAttributedString(tp: tp, isDark: isDark, showRepeat: showRepeatHighlight)
                coord.baseStorage = attrStr
                textView.textStorage?.setAttributedString(attrStr)
            } else {
                coord.baseStorage = nil
                textView.textStorage?.setAttributedString(
                    NSAttributedString(string: "Open a .txt or .epub file to begin.",
                                       attributes: placeholderAttrs())
                )
            }
        }

        guard let tp = textProcessor,
              let storage = textView.textStorage else { return }

        // --- Handle stopped state: restore previous sentence from base ---
        if speech.currentSentenceIndex == nil, let prevIdx = coord.lastSentenceIdx {
            // Restore from base
            if let base = coord.baseStorage, prevIdx < tp.sentences.count {
                let r = tp.sentences[prevIdx].range
                if NSMaxRange(r) <= storage.length {
                    base.enumerateAttributes(in: r, options: []) { attrs, subRange, _ in
                        storage.setAttributes(attrs, range: subRange)
                    }
                }
            }
            coord.lastSentenceIdx = nil
            coord.lastWordRange = nil
            return
        }

        // --- Restore previous sentence to DIM state ---
        if let prevIdx = coord.lastSentenceIdx,
           prevIdx != speech.currentSentenceIndex,
           prevIdx < tp.sentences.count {
            if let base = coord.baseStorage {
                let r = tp.sentences[prevIdx].range
                if NSMaxRange(r) <= storage.length {
                    base.enumerateAttributes(in: r, options: []) { attrs, subRange, _ in
                        storage.setAttributes(attrs, range: subRange)
                    }
                }
            }
        }

        // --- Apply current sentence: bright text + tint background ---
        if let idx = speech.currentSentenceIndex,
           idx != coord.lastSentenceIdx,
           idx < tp.sentences.count {
            let r = tp.sentences[idx].range
            if NSMaxRange(r) <= storage.length {
                applyActiveSentenceAttrs(to: storage, range: r, tp: tp, isDark: isDark, showRepeat: showRepeatHighlight)
            }
        }
        let sentenceChanged = coord.lastSentenceIdx != speech.currentSentenceIndex
        coord.lastSentenceIdx = speech.currentSentenceIndex
        // When the sentence advances, the previous word lives in the sentence we just
        // dimmed — clear it so the word-restore step below doesn't re-brighten it.
        if sentenceChanged { coord.lastWordRange = nil }

        // --- Restore previous word to sentence-bright attrs ---
        if let prevWordRange = coord.lastWordRange {
            if NSMaxRange(prevWordRange) <= storage.length {
                let isRepeat = tp.repeatedWordLocations.contains(prevWordRange.location)
                // Restore to active-sentence styling (not dim)
                let attrs = activeSentenceWordAttrs(repeated: isRepeat, isDark: isDark, showRepeat: showRepeatHighlight)
                storage.addAttributes(attrs, range: prevWordRange)
                // Re-apply sentence background tint
                if let sentIdx = speech.currentSentenceIndex,
                   sentIdx < tp.sentences.count {
                    let sentRange = tp.sentences[sentIdx].range
                    let inter = NSIntersectionRange(prevWordRange, sentRange)
                    if inter.length > 0 {
                        storage.addAttribute(.backgroundColor,
                                             value: Theme.sentenceHighlight(isDark),
                                             range: inter)
                    }
                }
            }
        }

        // --- Apply current word highlight ---
        if let wordRange = speech.currentWordRange {
            if NSMaxRange(wordRange) <= storage.length {
                storage.addAttributes(wordHighlightAttrs(), range: wordRange)
                coord.lastWordRange = wordRange
                scrollToRange(wordRange, in: textView, scrollView: scrollView)
            }
        } else {
            coord.lastWordRange = nil
        }
    }

    // MARK: - Attributed string construction

    private func buildBaseAttributedString(tp: TextProcessor, isDark: Bool, showRepeat: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString(string: tp.fullText,
                                               attributes: dimTextAttrs(isDark: isDark))
        if showRepeat {
            for loc in tp.repeatedWordLocations {
                if let token = tp.wordToken(containing: loc) {
                    let r = token.range
                    if NSMaxRange(r) <= (tp.fullText as NSString).length {
                        result.addAttributes(dimRepeatAttrs(isDark: isDark), range: r)
                    }
                }
            }
        }
        return result
    }

    private func applyActiveSentenceAttrs(to storage: NSTextStorage, range: NSRange,
                                           tp: TextProcessor, isDark: Bool, showRepeat: Bool) {
        // First set the whole sentence to bright text + sentence background
        let bgColor = Theme.sentenceHighlight(isDark)
        let fgColor = Theme.activeText(isDark)
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = Theme.lineHeightMult

        let baseAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: fgColor,
            .backgroundColor: bgColor,
            .font: Theme.font,
            .paragraphStyle: style
        ]
        storage.addAttributes(baseAttrs, range: range)

        // Then color repeated words in active orange
        if showRepeat {
            let repeatedAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: Theme.repeatedActive(isDark),
                .backgroundColor: bgColor,
                .font: Theme.font,
                .paragraphStyle: style
            ]
            for loc in tp.repeatedWordLocations {
                if let token = tp.wordToken(containing: loc) {
                    let inter = NSIntersectionRange(token.range, range)
                    if inter.length > 0 {
                        storage.addAttributes(repeatedAttrs, range: inter)
                    }
                }
            }
        }
    }

    private func activeSentenceWordAttrs(repeated: Bool, isDark: Bool, showRepeat: Bool) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = Theme.lineHeightMult
        let bgColor = Theme.sentenceHighlight(isDark)
        if repeated && showRepeat {
            return [
                .foregroundColor: Theme.repeatedActive(isDark),
                .backgroundColor: bgColor,
                .font: Theme.font,
                .paragraphStyle: style
            ]
        }
        return [
            .foregroundColor: Theme.activeText(isDark),
            .backgroundColor: bgColor,
            .font: Theme.font,
            .paragraphStyle: style
        ]
    }

    private func dimTextAttrs(isDark: Bool) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = Theme.lineHeightMult
        style.alignment = .left
        return [
            .font: Theme.font,
            .foregroundColor: Theme.dimText(isDark),
            .backgroundColor: Theme.background(isDark),
            .paragraphStyle: style
        ]
    }

    private func dimRepeatAttrs(isDark: Bool) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = Theme.lineHeightMult
        return [
            .foregroundColor: Theme.repeatedDim(isDark),
            .backgroundColor: Theme.background(isDark),
            .paragraphStyle: style,
            .font: Theme.font
        ]
    }

    private func placeholderAttrs() -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 16, weight: .light),
         .foregroundColor: NSColor.secondaryLabelColor]
    }

    private func wordHighlightAttrs() -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = Theme.lineHeightMult
        return [.foregroundColor: Theme.wordHighlightFg,
                .backgroundColor: Theme.wordHighlight,
                .paragraphStyle: style,
                .font: Theme.font]
    }

    // MARK: - Auto-scroll

    private func scrollToRange(_ range: NSRange, in textView: NSTextView, scrollView: NSScrollView) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        // With allowsNonContiguousLayout = true, ensureLayout only processes this
        // fragment — not all preceding text — so the call is O(local) not O(document).
        layoutManager.ensureLayout(forCharacterRange: range)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range,
                                                   actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect = rect.offsetBy(dx: textView.textContainerInset.width,
                              dy: textView.textContainerInset.height)
        let padded = rect.insetBy(dx: 0, dy: -80)
        textView.scrollToVisible(padded)
    }

    // MARK: - Coordinator

    final class Coordinator {
        weak var textView: ClickableTextView?
        weak var scrollView: NSScrollView?
        var loadedText: TextProcessor?
        var lastWordRange: NSRange?
        var lastSentenceIdx: Int?
        var speechRef: (() -> Void)?
        var baseStorage: NSAttributedString?
        var lastIsDark: Bool?
        var lastShowRepeat: Bool?
    }
}
