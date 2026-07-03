import SwiftUI
import AppKit

// MARK: - Bridge to the NSTextView inside HighlightedTextView

/// Lets ContentView read the current selection and scroll the reading view
/// without owning the NSTextView directly.
final class TextViewProxy {
    weak var textView: NSTextView?

    func selectedRange() -> NSRange? {
        guard let tv = textView else { return nil }
        let r = tv.selectedRange()
        return r.length > 0 ? r : nil
    }

    func scroll(to range: NSRange) {
        textView?.scrollRangeToVisible(range)
    }

    /// Collapse the selection to its start (after playback jumps there).
    func collapseSelection() {
        guard let tv = textView else { return }
        tv.setSelectedRange(NSRange(location: tv.selectedRange().location, length: 0))
    }

    /// Drive the text view's native find bar (show, next/previous match, …).
    func performFind(_ action: NSTextFinder.Action) {
        guard let tv = textView else { return }
        tv.window?.makeFirstResponder(tv)
        let item = NSMenuItem()
        item.tag = action.rawValue
        tv.performTextFinderAction(item)
    }
}

// MARK: - Draft model for the editor sheet

struct NoteDraft: Identifiable {
    let id = UUID()
    var existing: Note?
    var kind: NoteKind
    var range: NSRange
    var quote: String
    var content: String = ""
}

// MARK: - Editor sheet

struct NoteEditorSheet: View {
    @State var draft: NoteDraft
    let onSave: (NoteDraft) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Kind", selection: $draft.kind) {
                Text("Comment").tag(NoteKind.comment)
                Text("Revision").tag(NoteKind.revision)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if !draft.quote.isEmpty {
                Text(draft.quote)
                    .italic()
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(4)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(6)
            }

            Text(draft.kind == .revision ? "Suggested revision:" : "Comment:")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            TextEditor(text: $draft.content)
                .font(.system(size: 13))
                .frame(minHeight: 110)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1))

            HStack {
                Text("\u{2318}\u{21A9} to save")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(draft.existing == nil ? "Add Note" : "Save") {
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 440)
    }
}

// MARK: - Notes sidebar

struct NotesPanel: View {
    let notes: [Note]
    let isDark: Bool
    let onSelect: (Note) -> Void
    let onEdit: (Note) -> Void
    let onDelete: (Note) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 6) {
                if notes.isEmpty {
                    Text("No notes yet.\n\nSelect text and right-click, or press \u{21E7}\u{2318}C while listening to comment on the current sentence.")
                        .font(.system(size: 12))
                        .foregroundColor(isDark ? Color(white: 0.50) : Color(white: 0.45))
                        .padding(12)
                } else {
                    ForEach(notes) { note in
                        NoteRow(note: note, isDark: isDark,
                                onSelect: { onSelect(note) },
                                onEdit:   { onEdit(note) },
                                onDelete: { onDelete(note) })
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
        }
        .frame(width: 260)
        .background(
            isDark
                ? Color(nsColor: NSColor(white: 0.08, alpha: 1))
                : Color(nsColor: NSColor(white: 0.92, alpha: 1))
        )
    }
}

private struct NoteRow: View {
    let note: Note
    let isDark: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var kindColor: Color {
        note.kind == .revision
            ? Color(nsColor: Theme.repeatedActive(isDark))
            : Color(nsColor: Theme.noteAccent)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: note.kind == .revision ? "pencil.line" : "text.bubble")
                        .font(.system(size: 10))
                        .foregroundColor(kindColor)
                    Text(note.kind == .revision ? "Revision" : "Comment")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(kindColor)
                }
                if !note.quote.isEmpty {
                    Text("\u{201C}\(note.quote)\u{201D}")
                        .font(.system(size: 11))
                        .italic()
                        .foregroundColor(isDark ? Color(white: 0.50) : Color(white: 0.45))
                        .lineLimit(2)
                }
                Text(note.content)
                    .font(.system(size: 12))
                    .foregroundColor(isDark ? Color(white: 0.78) : Color(white: 0.18))
                    .lineLimit(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isDark ? Color(white: 0.12) : Color(white: 0.88))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit\u{2026}") { onEdit() }
            Divider()
            Button("Copy Note") { copyToPasteboard(note.content) }
            if !note.quote.isEmpty {
                Button("Copy Quote") { copyToPasteboard(note.quote) }
            }
            Divider()
            Button("Delete") { onDelete() }
        }
        .accessibilityLabel("\(note.kind == .revision ? "Revision" : "Comment"): \(note.content)")
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
