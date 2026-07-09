import SwiftUI

/// Shared flags the menu bar uses to enable/disable commands.
final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var documentLoaded = false
    @Published var hasChapters = false
    @Published var hasNotes = false
    private init() {}
}

@main
struct ScrivenerReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var recents = RecentFilesManager.shared
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 700, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
        // File opens are handled by the AppDelegate (application(_:open:)) and
        // routed by notification into the existing window. Claiming external
        // events here would make SwiftUI spawn a second, blank window when the
        // app is launched with a file (e.g. compiled from Scrivener).
        .handlesExternalEvents(matching: [])
        .commands {
            // ── File menu ─────────────────────────────────────────────────────
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("Open File…") {
                    NotificationCenter.default.post(name: .openFileRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Menu("Open Recent") {
                    if recents.urls.isEmpty {
                        Text("No Recent Files")
                    } else {
                        ForEach(recents.urls, id: \.absoluteString) { url in
                            Button(url.lastPathComponent) {
                                NotificationCenter.default.post(name: .openFileURL, object: url)
                            }
                        }
                        Divider()
                        Button("Clear Menu") { recents.clear() }
                    }
                }

                Divider()

                Button("Export as MP3\u{2026}") {
                    NotificationCenter.default.post(name: .exportAudioRequested, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!appState.documentLoaded)

                Divider()

                Button("Close") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            // ── File menu: Print ──────────────────────────────────────────────
            CommandGroup(replacing: .printItem) {
                Button("Print\u{2026}") {
                    NotificationCenter.default.post(name: .printRequested, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(!appState.documentLoaded)
            }

            // ── Playback menu ─────────────────────────────────────────────────
            CommandMenu("Playback") {
                Button("Play / Pause") {
                    NotificationCenter.default.post(name: .playPauseRequested, object: nil)
                }
                .disabled(!appState.documentLoaded)

                Divider()

                Button("Previous Chapter") {
                    NotificationCenter.default.post(name: .prevChapterRequested, object: nil)
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(!appState.documentLoaded)

                Button("Next Chapter") {
                    NotificationCenter.default.post(name: .nextChapterRequested, object: nil)
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(!appState.documentLoaded)

                Divider()

                Button("Slower") {
                    NotificationCenter.default.post(name: .speedDownRequested, object: nil)
                }
                .keyboardShortcut("[", modifiers: [])

                Button("Faster") {
                    NotificationCenter.default.post(name: .speedUpRequested, object: nil)
                }
                .keyboardShortcut("]", modifiers: [])
            }

            // ── Edit menu: Find ───────────────────────────────────────────────
            CommandGroup(after: .textEditing) {
                Button("Find\u{2026}") {
                    NotificationCenter.default.post(name: .findRequested, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!appState.documentLoaded)

                Button("Find Next") {
                    NotificationCenter.default.post(name: .findNextRequested, object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(!appState.documentLoaded)

                Button("Find Previous") {
                    NotificationCenter.default.post(name: .findPreviousRequested, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(!appState.documentLoaded)

                Button("Use Selection for Find") {
                    NotificationCenter.default.post(name: .useSelectionForFindRequested, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!appState.documentLoaded)
            }

            // ── View menu ─────────────────────────────────────────────────────
            CommandMenu("View") {
                Button("Toggle Table of Contents") {
                    NotificationCenter.default.post(name: .toggleTOCRequested, object: nil)
                }
                .keyboardShortcut("\\", modifiers: .command)
                .disabled(!appState.hasChapters)

                Button("Toggle Notes") {
                    NotificationCenter.default.post(name: .toggleNotesRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!appState.documentLoaded)

                Divider()

                Button("Make Text Bigger") {
                    NotificationCenter.default.post(name: .textBiggerRequested, object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Make Text Smaller") {
                    NotificationCenter.default.post(name: .textSmallerRequested, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") {
                    NotificationCenter.default.post(name: .textActualSizeRequested, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)
            }

            // ── Notes menu ────────────────────────────────────────────────────
            CommandMenu("Notes") {
                Button("Add Comment\u{2026}") {
                    NotificationCenter.default.post(name: .addCommentRequested, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!appState.documentLoaded)

                Button("Suggest Revision\u{2026}") {
                    NotificationCenter.default.post(name: .addRevisionRequested, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!appState.documentLoaded)

                Divider()

                Button("Export Notes\u{2026}") {
                    NotificationCenter.default.post(name: .exportNotesRequested, object: nil)
                }
                .disabled(!appState.hasNotes)
            }

            // ── Help menu ─────────────────────────────────────────────────────
            CommandGroup(replacing: .help) {
                Button("Storyteller Help") {
                    NotificationCenter.default.post(name: .showHelp, object: nil)
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }

        Window("Storyteller Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)
    }
}

// MARK: - App Delegate (receives files opened by Scrivener / Finder)

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// File handed to us at launch, buffered until ContentView is listening.
    /// The open event often arrives before the SwiftUI view subscribes to
    /// notifications, which used to leave a blank window at launch.
    var pendingURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        settleWindowsAndDeliver()
    }

    /// SwiftUI spawns an extra window for external open events (both at cold
    /// launch and while running). After things settle: close the duplicates,
    /// then deliver any pending file to the surviving window — the immediate
    /// notification can be missed (cold launch) or land in a window that gets
    /// closed, so the survivor is fed explicitly.
    private func settleWindowsAndDeliver() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            Self.closeDuplicateMainWindows()
            if let url = self?.pendingURL {
                self?.pendingURL = nil
                NotificationCenter.default.post(name: .openFileURL, object: url)
            }
        }
    }

    private static func closeDuplicateMainWindows() {
        let mains = NSApp.windows.filter {
            $0.isVisible && $0.styleMask.contains(.closable) && $0.frame.width >= 500
        }
        guard mains.count > 1 else { return }
        let keep = NSApp.mainWindow ?? mains.first!
        for w in mains where w !== keep { w.close() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        pendingURL = url
        NotificationCenter.default.post(name: .openFileURL, object: url)
        settleWindowsAndDeliver()
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        pendingURL = url
        NotificationCenter.default.post(name: .openFileURL, object: url)
        settleWindowsAndDeliver()
        return true
    }

    /// System Services entry point — "Read in Storyteller" on any selected text.
    @objc func readText(_ pboard: NSPasteboard, userData: String, error: NSErrorPointer) {
        guard let text = pboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Selected Text.txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch { return }
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .openFileURL, object: url)
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let openFileRequested  = Notification.Name("openFileRequested")
    static let openFileURL        = Notification.Name("openFileURL")
    static let showHelp           = Notification.Name("showHelp")
    static let playPauseRequested = Notification.Name("playPauseRequested")
    static let nextChapterRequested = Notification.Name("nextChapterRequested")
    static let prevChapterRequested = Notification.Name("prevChapterRequested")
    static let speedUpRequested   = Notification.Name("speedUpRequested")
    static let speedDownRequested = Notification.Name("speedDownRequested")
    static let toggleTOCRequested = Notification.Name("toggleTOCRequested")
    static let toggleNotesRequested = Notification.Name("toggleNotesRequested")
    static let addCommentRequested  = Notification.Name("addCommentRequested")
    static let addRevisionRequested = Notification.Name("addRevisionRequested")
    static let exportNotesRequested = Notification.Name("exportNotesRequested")
    static let findRequested         = Notification.Name("findRequested")
    static let findNextRequested     = Notification.Name("findNextRequested")
    static let findPreviousRequested = Notification.Name("findPreviousRequested")
    static let useSelectionForFindRequested = Notification.Name("useSelectionForFindRequested")
    static let exportAudioRequested = Notification.Name("exportAudioRequested")
    static let printRequested          = Notification.Name("printRequested")
    static let textBiggerRequested     = Notification.Name("textBiggerRequested")
    static let textSmallerRequested    = Notification.Name("textSmallerRequested")
    static let textActualSizeRequested = Notification.Name("textActualSizeRequested")
}
