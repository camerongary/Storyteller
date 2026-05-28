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
            // Replace default New with Open
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("Open File…") {
                    NotificationCenter.default.post(name: .openFileRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                // Open Recent submenu
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
                        Button("Clear Menu") {
                            recents.clear()
                        }
                    }
                }
            }

            // Help menu item
            CommandGroup(replacing: .help) {
                Button("Storyteller Help") {
                    NotificationCenter.default.post(name: .showHelp, object: nil)
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }

        // Dedicated Help window (separate from main window)
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
    static let openFileRequested = Notification.Name("openFileRequested")
    static let openFileURL       = Notification.Name("openFileURL")
    static let showHelp          = Notification.Name("showHelp")
}
