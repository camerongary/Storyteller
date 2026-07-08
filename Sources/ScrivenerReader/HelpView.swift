import SwiftUI
import AppKit

struct HelpView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            Color(nsColor: isDark
                ? NSColor(srgbRed: 0.10, green: 0.10, blue: 0.10, alpha: 1)
                : NSColor(srgbRed: 0.97, green: 0.96, blue: 0.93, alpha: 1))
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 24) {

                    // Opening Files
                    helpSection(title: "Opening Files") {
                        bodyText(
                            "Drag a file onto the app window or use File \u{203A} Open (\u{2318}O). Supported formats: .txt, .epub, .pdf, and .rtf/.rtfd."
                        )
                    }

                    // Playback
                    helpSection(title: "Playback") {
                        shortcutTable(rows: [
                            ("Play / Pause", "Space  or  \u{25B6} button"),
                            ("Previous chapter / sentence", "\u{2318}\u{2190}"),
                            ("Next chapter / sentence", "\u{2318}\u{2192}"),
                            ("Toggle Table of Contents", "\u{2318}\\"),
                            ("Jump to word", "Click any word"),
                        ])
                    }

                    // Speed
                    helpSection(title: "Speed") {
                        shortcutTable(rows: [
                            ("Slower", "\u{1F422} button or  [  key"),
                            ("Faster", "\u{1F407} button or  ]  key"),
                        ])
                    }

                    // Text size
                    helpSection(title: "Text Size") {
                        shortcutTable(rows: [
                            ("Bigger", "\u{2318}+"),
                            ("Smaller", "\u{2318}\u{2212}"),
                            ("Actual size", "\u{2318}0"),
                        ])
                    }

                    // System integration
                    helpSection(title: "Anywhere on your Mac") {
                        bodyText(
                            "Select text in any app and choose <App> \u{203A} Services \u{203A} Read in Storyteller to hear it read aloud. Print the open document with \u{2318}P."
                        )
                    }

                    // Highlighting
                    helpSection(title: "Highlighting") {
                        VStack(alignment: .leading, spacing: 6) {
                            bulletText("The current sentence is brightened; all other text is dimmed.")
                            bulletText("The current word gets a yellow highlight.")
                            bulletText("Repeated content words are shown in orange. Toggle this with the repeat button (\u{21BB}) in the toolbar.")
                        }
                    }

                    // Notes
                    helpSection(title: "Notes") {
                        VStack(alignment: .leading, spacing: 6) {
                            bulletText("Select text and right-click to add a comment or suggest a revision.")
                            bulletText("While listening, press \u{21E7}\u{2318}C (comment) or \u{21E7}\u{2318}R (revision) to annotate the current sentence \u{2014} playback pauses while you write.")
                            bulletText("Annotated passages get a dotted underline. Toggle the notes panel with \u{21E7}\u{2318}N; click a note to jump to its place in the text.")
                            bulletText("Notes are saved per document and restored when you reopen it. Use Notes \u{203A} Export Notes\u{2026} to save them as Markdown.")
                        }
                    }

                    // Voices
                    helpSection(title: "Voices") {
                        bodyText(
                            "Choose from the Voice menu in the toolbar. Note: macOS Siri voices (Voice 1/2/3 in System Settings) are not available to third-party apps — Ava (Premium) is the highest quality alternative."
                        )
                    }

                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
        }
        .frame(width: 500, height: 480)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func helpSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isDark
                    ? Color(nsColor: NSColor(srgbRed: 0.90, green: 0.50, blue: 0.20, alpha: 1))
                    : Color(nsColor: NSColor(srgbRed: 0.60, green: 0.28, blue: 0.06, alpha: 1)))
            content()
        }
    }

    @ViewBuilder
    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(isDark ? Color(white: 0.78) : Color(white: 0.20))
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(3)
    }

    @ViewBuilder
    private func bulletText(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\u{2022}")
                .font(.system(size: 13))
                .foregroundColor(isDark ? Color(white: 0.55) : Color(white: 0.45))
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(isDark ? Color(white: 0.78) : Color(white: 0.20))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
    }

    @ViewBuilder
    private func shortcutTable(rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 0) {
                    Text(row.0)
                        .font(.system(size: 13))
                        .foregroundColor(isDark ? Color(white: 0.78) : Color(white: 0.20))
                        .frame(width: 170, alignment: .leading)
                    Text(row.1)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(isDark ? Color(white: 0.60) : Color(white: 0.35))
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    index % 2 == 0
                        ? (isDark ? Color(white: 0.14) : Color(white: 0.91))
                        : Color.clear
                )
                .cornerRadius(4)
            }
        }
    }
}
