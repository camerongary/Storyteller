import SwiftUI

@main
struct ScrivenerReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var recents = RecentFilesManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 700, minHeight: 500)
                .onOpenURL { url in
                    NotificationCenter.default.post(name: .openFileURL, object: url)
                }
        }
        .windowStyle(.hiddenTitleBar)
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

                Button("Close") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            // ── Playback menu ─────────────────────────────────────────────────
            CommandMenu("Playback") {
                Button("Play / Pause") {
                    NotificationCenter.default.post(name: .playPauseRequested, object: nil)
                }

                Divider()

                Button("Previous Chapter") {
                    NotificationCenter.default.post(name: .prevChapterRequested, object: nil)
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)

                Button("Next Chapter") {
                    NotificationCenter.default.post(name: .nextChapterRequested, object: nil)
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

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

            // ── View menu ─────────────────────────────────────────────────────
            CommandMenu("View") {
                Button("Toggle Table of Contents") {
                    NotificationCenter.default.post(name: .toggleTOCRequested, object: nil)
                }
                .keyboardShortcut("\\", modifiers: .command)
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
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        NotificationCenter.default.post(name: .openFileURL, object: url)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        NotificationCenter.default.post(name: .openFileURL, object: url)
        return true
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
}
