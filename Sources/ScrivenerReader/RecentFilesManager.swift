import Foundation
import Combine

/// Remembers the reading position per document so reopening a file
/// resumes where the user left off.
enum ReadingPosition {
    private static func key(for url: URL) -> String { "readingPosition:\(url.path)" }

    static func save(_ offset: Int, for url: URL) {
        UserDefaults.standard.set(offset, forKey: key(for: url))
    }

    static func load(for url: URL) -> Int? {
        let v = UserDefaults.standard.integer(forKey: key(for: url))
        return v > 0 ? v : nil
    }
}

/// Persists up to 10 recently opened file URLs across launches.
/// Uses security-scoped bookmarks so sandboxed access is preserved.
final class RecentFilesManager: ObservableObject {
    static let shared = RecentFilesManager()

    @Published private(set) var urls: [URL] = []

    private let maxCount = 10
    private let defaultsKey = "recentFileBookmarks"

    private init() {
        load()
    }

    // MARK: - Public API

    func add(_ url: URL) {
        var fresh = urls.filter { $0.absoluteString != url.absoluteString }
        fresh.insert(url, at: 0)
        if fresh.count > maxCount { fresh = Array(fresh.prefix(maxCount)) }
        urls = fresh
        save()
    }

    func clear() {
        urls = []
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    // MARK: - Persistence (plain paths — app is not sandboxed)

    private func save() {
        let paths = urls.map { $0.path }
        UserDefaults.standard.set(paths, forKey: defaultsKey)
    }

    private func load() {
        guard let paths = UserDefaults.standard.stringArray(forKey: defaultsKey) else { return }
        urls = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
