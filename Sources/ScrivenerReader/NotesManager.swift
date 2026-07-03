import Foundation
import Combine
import CryptoKit

enum NoteKind: String, Codable {
    case comment
    case revision
}

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: NoteKind
    var location: Int
    var length: Int
    var quote: String
    var content: String
    var created: Date

    var range: NSRange { NSRange(location: location, length: length) }
}

/// Stores notes per document as JSON in Application Support, keyed by a hash
/// of the source file's path. Notes are re-anchored by their quoted text when
/// the document's contents have shifted since they were made.
final class NotesManager: ObservableObject {
    @Published private(set) var notes: [Note] = [] {
        didSet { AppState.shared.hasNotes = !notes.isEmpty }
    }
    private var documentURL: URL?

    private static let dir: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Storyteller/Notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private func fileURL(for doc: URL) -> URL {
        let digest = SHA256.hash(data: Data(doc.path.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined().prefix(24)
        return Self.dir.appendingPathComponent("\(name).json")
    }

    // MARK: - Load / save

    func load(for doc: URL, text: String) {
        documentURL = doc
        guard let data = try? Data(contentsOf: fileURL(for: doc)),
              var loaded = try? JSONDecoder().decode([Note].self, from: data) else {
            notes = []
            return
        }
        // Re-anchor notes whose stored range no longer matches the text.
        let ns = text as NSString
        for i in loaded.indices {
            let n = loaded[i]
            guard !n.quote.isEmpty else { continue }
            let inBounds = NSMaxRange(n.range) <= ns.length
            if inBounds && ns.substring(with: n.range) == n.quote { continue }
            let found = ns.range(of: n.quote)
            if found.location != NSNotFound {
                loaded[i].location = found.location
                loaded[i].length   = found.length
            } else if !inBounds {
                loaded[i].location = 0
                loaded[i].length   = 0
            }
        }
        notes = loaded.sorted { $0.location < $1.location }
    }

    private func save() {
        guard let doc = documentURL else { return }
        if let data = try? JSONEncoder().encode(notes) {
            try? data.write(to: fileURL(for: doc))
        }
    }

    // MARK: - Mutation (undoable)

    func add(kind: NoteKind, range: NSRange, quote: String, content: String,
             undoManager: UndoManager? = nil) {
        let note = Note(id: UUID(), kind: kind,
                        location: range.location, length: range.length,
                        quote: quote, content: content, created: Date())
        insert(note, undoManager: undoManager, actionName: "Add Note")
    }

    func update(_ note: Note, undoManager: UndoManager? = nil) {
        guard let i = notes.firstIndex(where: { $0.id == note.id }) else { return }
        let old = notes[i]
        notes[i] = note
        save()
        undoManager?.registerUndo(withTarget: self) { mgr in
            mgr.update(old, undoManager: undoManager)
        }
        undoManager?.setActionName("Edit Note")
    }

    func delete(_ note: Note, undoManager: UndoManager? = nil) {
        notes.removeAll { $0.id == note.id }
        save()
        undoManager?.registerUndo(withTarget: self) { mgr in
            mgr.insert(note, undoManager: undoManager, actionName: "Delete Note")
        }
        undoManager?.setActionName("Delete Note")
    }

    private func insert(_ note: Note, undoManager: UndoManager?, actionName: String) {
        notes.append(note)
        notes.sort { $0.location < $1.location }
        save()
        undoManager?.registerUndo(withTarget: self) { mgr in
            mgr.delete(note, undoManager: undoManager)
        }
        undoManager?.setActionName(actionName)
    }

    // MARK: - Export

    func exportMarkdown(documentName: String) -> String {
        var out = "# Notes — \(documentName)\n"
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        for n in notes {
            out += "\n---\n\n"
            if !n.quote.isEmpty {
                out += "> \(n.quote.replacingOccurrences(of: "\n", with: "\n> "))\n\n"
            }
            out += n.kind == .revision ? "**Revision:** \(n.content)\n"
                                       : "**Comment:** \(n.content)\n"
            out += "\n*\(df.string(from: n.created))*\n"
        }
        if notes.isEmpty { out += "\nNo notes.\n" }
        return out
    }
}
