import SwiftUI

struct TOCPanel: View {
    let chapters: [(title: String, charOffset: Int)]
    let activeIndex: Int?
    let isDark: Bool
    let onSelect: (Int) -> Void   // charOffset

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(chapters.enumerated()), id: \.offset) { i, ch in
                        TOCRow(
                            title:    ch.title,
                            isActive: activeIndex == i,
                            isDark:   isDark
                        ) {
                            onSelect(ch.charOffset)
                        }
                        .id(i)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
            }
            // Auto-scroll to keep the active chapter visible
            .onChange(of: activeIndex) { idx in
                if let idx {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 220)
        .background(
            isDark
                ? Color(nsColor: NSColor(white: 0.08, alpha: 1))
                : Color(nsColor: NSColor(white: 0.92, alpha: 1))
        )
    }
}

// MARK: - Row

private struct TOCRow: View {
    let title: String
    let isActive: Bool
    let isDark: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundColor(
                    isActive
                        ? Color(nsColor: Theme.repeatedActive(isDark))
                        : (isDark ? Color(white: 0.72) : Color(white: 0.22))
                )
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isActive
                        ? (isDark
                            ? Color(nsColor: NSColor(white: 0.16, alpha: 1))
                            : Color(nsColor: NSColor(white: 0.84, alpha: 1)))
                        : Color.clear
                )
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }
}
