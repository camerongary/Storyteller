import Foundation
import AppKit
import PDFKit

// MARK: - Output types

struct LoadedDocument {
    let text: String
    let chapters: [(title: String, charOffset: Int)]
}

// MARK: - Errors

enum LoadError: Error, LocalizedError {
    case unsupportedFormat
    case readFailed(String)
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Unsupported file format. Please use .txt, .epub, or .pdf."
        case .readFailed(let msg): return "Could not read file: \(msg)"
        case .parseFailed(let msg): return "Could not parse file: \(msg)"
        }
    }
}

// MARK: - Loader

struct DocumentLoader {

    static func load(url: URL) async throws -> LoadedDocument {
        switch url.pathExtension.lowercased() {
        case "txt":  return try loadTxt(url: url)
        case "epub": return try await loadEpub(url: url)
        case "pdf":  return try loadPDF(url: url)
        default:     throw LoadError.unsupportedFormat
        }
    }

    // =========================================================================
    // MARK: - TXT
    // =========================================================================

    private static func loadTxt(url: URL) throws -> LoadedDocument {
        let encodings: [String.Encoding] = [.utf8, .utf16, .isoLatin1, .windowsCP1252]
        for enc in encodings {
            if let text = try? String(contentsOf: url, encoding: enc) {
                return LoadedDocument(text: text, chapters: detectTxtChapters(in: text))
            }
        }
        throw LoadError.readFailed("Could not decode file with any standard encoding.")
    }

    /// Detect chapter-heading lines in plain text.
    /// Matches lines beginning with common structural keywords.
    private static func detectTxtChapters(in text: String) -> [(title: String, charOffset: Int)] {
        guard let re = try? NSRegularExpression(
            pattern: #"^(?:Chapter|CHAPTER|Part|PART|Book|BOOK|Section|SECTION|"# +
                     #"Prologue|PROLOGUE|Epilogue|EPILOGUE|Preface|PREFACE|"# +
                     #"Introduction|INTRODUCTION|Afterword|AFTERWORD)\b.{0,80}$"#,
            options: [.anchorsMatchLines])
        else { return [] }

        var chapters: [(title: String, charOffset: Int)] = []
        let ns = text as NSString
        re.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            let title = ns.substring(with: m.range).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { chapters.append((title, m.range.location)) }
        }
        return chapters
    }

    // =========================================================================
    // MARK: - PDF
    // =========================================================================

    private static func loadPDF(url: URL) throws -> LoadedDocument {
        guard let pdf = PDFDocument(url: url) else {
            throw LoadError.readFailed("Could not open PDF.")
        }

        // Extract text page-by-page, recording each page's char offset.
        var pageTexts: [(pageIndex: Int, text: String)] = []
        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i),
                  let raw  = page.string else { continue }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { pageTexts.append((i, text)) }
        }
        guard !pageTexts.isEmpty else {
            throw LoadError.parseFailed("No readable text found in PDF. The file may be scanned or image-only.")
        }

        // Build page-index → char-offset map (pages separated by "\n\n")
        var pageToOffset: [Int: Int] = [:]
        var running = 0
        for (idx, entry) in pageTexts.enumerated() {
            pageToOffset[entry.pageIndex] = running
            running += entry.text.count
            if idx + 1 < pageTexts.count { running += 2 }
        }

        let fullText = pageTexts.map(\.text).joined(separator: "\n\n")

        // Use the PDF's built-in outline (bookmarks) as chapters when available.
        var chapters: [(title: String, charOffset: Int)] = []
        if let outline = pdf.outlineRoot, outline.numberOfChildren > 0 {
            chapters = extractPDFOutline(outline, pdf: pdf, pageToOffset: pageToOffset)
        }

        return LoadedDocument(text: fullText, chapters: chapters)
    }

    /// Recursively walk the PDFOutline tree, mapping each entry to a char offset.
    private static func extractPDFOutline(
        _ node: PDFOutline,
        pdf: PDFDocument,
        pageToOffset: [Int: Int]
    ) -> [(title: String, charOffset: Int)] {
        var result: [(title: String, charOffset: Int)] = []
        var seen   = Set<Int>()

        func visit(_ n: PDFOutline) {
            for i in 0..<n.numberOfChildren {
                guard let child = n.child(at: i) else { continue }
                if let label  = child.label?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !label.isEmpty,
                   let dest   = child.destination,
                   let page   = dest.page,
                   let offset = pageToOffset[pdf.index(for: page)],
                   !seen.contains(offset) {
                    seen.insert(offset)
                    result.append((title: label, charOffset: offset))
                }
                visit(child)
            }
        }

        visit(node)
        return result.sorted { $0.charOffset < $1.charOffset }
    }

    // =========================================================================
    // MARK: - EPUB
    // =========================================================================

    private static func loadEpub(url: URL) async throws -> LoadedDocument {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScrivReader_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-o", "-q", url.path, "-d", tempDir.path]
        proc.standardError = Pipe()
        proc.standardOutput = Pipe()
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw LoadError.parseFailed("unzip failed (status \(proc.terminationStatus))")
        }

        return try extractEpubContent(from: tempDir)
    }

    private static func extractEpubContent(from dir: URL) throws -> LoadedDocument {
        let opfURL = locateOPF(in: dir)

        var htmlURLs: [URL] = opfURL.map { orderedHTMLFiles(opfURL: $0) } ?? []
        if htmlURLs.isEmpty { htmlURLs = allHTMLFiles(in: dir) }
        guard !htmlURLs.isEmpty else {
            throw LoadError.parseFailed("No readable content found in epub.")
        }

        // ── Extract text from each file, recording its start offset ──────────
        var parts: [(url: URL, text: String)] = []
        for url in htmlURLs {
            if let t = htmlToText(url: url)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                parts.append((url: url.standardized, text: t))
            }
        }

        // Build offset map (url.standardized → char offset in fullText)
        var pathToOffset: [String: Int] = [:]
        var running = 0
        for (i, part) in parts.enumerated() {
            pathToOffset[part.url.path] = running
            running += part.text.count
            if i + 1 < parts.count { running += 2 }   // "\n\n" separator
        }

        let fullText = parts.map(\.text).joined(separator: "\n\n")

        // ── Parse table of contents ──────────────────────────────────────────
        var chapters: [(title: String, charOffset: Int)] = []
        if let opfURL {
            let base = opfURL.deletingLastPathComponent()
            chapters = parseEpubChapters(opfURL: opfURL, base: base, pathToOffset: pathToOffset)
        }

        return LoadedDocument(text: fullText, chapters: chapters)
    }

    // ── Chapter extraction ────────────────────────────────────────────────────

    private static func parseEpubChapters(opfURL: URL, base: URL,
                                           pathToOffset: [String: Int])
        -> [(title: String, charOffset: Int)]
    {
        guard let opfData = try? Data(contentsOf: opfURL),
              let opf = String(data: opfData, encoding: .utf8) else { return [] }

        // Try epub3 NAV document first
        if let navURL = findNavDocument(opf: opf, base: base),
           let navStr = try? String(contentsOf: navURL, encoding: .utf8) {
            let entries = parseNavTOC(navStr, tocBase: navURL.deletingLastPathComponent())
            let mapped = mapToOffsets(entries, pathToOffset: pathToOffset)
            if !mapped.isEmpty { return mapped }
        }

        // Fall back to epub2 NCX
        if let ncxURL = findNCX(opf: opf, base: base),
           let ncxStr = try? String(contentsOf: ncxURL, encoding: .utf8) {
            let entries = parseNCXTOC(ncxStr, tocBase: ncxURL.deletingLastPathComponent())
            return mapToOffsets(entries, pathToOffset: pathToOffset)
        }

        return []
    }

    // ── Locate TOC files ─────────────────────────────────────────────────────

    private static func findNavDocument(opf: String, base: URL) -> URL? {
        // <item properties="nav" href="…" …/>  — attributes in any order
        let patterns = [
            #"<item[^>]+properties="[^"]*\bnav\b[^"]*"[^>]+href="([^"]+)""#,
            #"<item[^>]+href="([^"]+)"[^>]+properties="[^"]*\bnav\b[^"]*""#,
        ]
        for pat in patterns {
            if let url = firstCapture(pat, in: opf).map({ decode($0, relativeTo: base) }) {
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }

    private static func findNCX(opf: String, base: URL) -> URL? {
        let patterns = [
            #"<item[^>]+media-type="application/x-dtbncx\+xml"[^>]+href="([^"]+)""#,
            #"<item[^>]+href="([^"]+)"[^>]+media-type="application/x-dtbncx\+xml""#,
        ]
        for pat in patterns {
            if let url = firstCapture(pat, in: opf).map({ decode($0, relativeTo: base) }) {
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        // Fallback: toc.ncx in same directory
        let candidate = base.appendingPathComponent("toc.ncx")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    // ── Parse epub3 NAV ───────────────────────────────────────────────────────

    private static func parseNavTOC(_ nav: String, tocBase: URL)
        -> [(title: String, resolvedURL: URL)]
    {
        // Isolate the <nav epub:type="toc"> section
        var section = nav
        if let re = try? NSRegularExpression(
            pattern: #"(?s)<nav[^>]+epub:type="toc"[^>]*>(.*?)</nav>"#),
           let m = re.firstMatch(in: nav, range: nsRange(nav)),
           let r = Range(m.range(at: 1), in: nav) {
            section = String(nav[r])
        }

        var results: [(String, URL)] = []
        guard let re = try? NSRegularExpression(
            pattern: #"<a[^>]+href="([^"]+)">([^<]+)</a>"#)
        else { return [] }

        re.enumerateMatches(in: section, range: nsRange(section)) { m, _, _ in
            guard let m,
                  let hr = Range(m.range(at: 1), in: section),
                  let tr = Range(m.range(at: 2), in: section)
            else { return }

            var href = String(section[hr])
            // Strip fragment
            if let h = href.firstIndex(of: "#") { href = String(href[href.startIndex..<h]) }
            guard !href.isEmpty else { return }

            let title = String(section[tr]).trimmingCharacters(in: .whitespacesAndNewlines)
            let url   = decode(href, relativeTo: tocBase)
            if !title.isEmpty { results.append((title, url)) }
        }
        return results
    }

    // ── Parse epub2 NCX ───────────────────────────────────────────────────────

    private static func parseNCXTOC(_ ncx: String, tocBase: URL)
        -> [(title: String, resolvedURL: URL)]
    {
        var results: [(String, URL)] = []
        guard let npRe = try? NSRegularExpression(
            pattern: #"(?s)<navPoint[^>]*?>(.*?)</navPoint>"#,
            options: [.dotMatchesLineSeparators])
        else { return [] }

        let textRe    = try? NSRegularExpression(pattern: "<text>([^<]*)</text>")
        let contentRe = try? NSRegularExpression(pattern: #"<content[^>]+src="([^"]+)""#)

        npRe.enumerateMatches(in: ncx, range: nsRange(ncx)) { m, _, _ in
            guard let m, let br = Range(m.range(at: 1), in: ncx) else { return }
            let block = String(ncx[br])
            let br2   = nsRange(block)

            guard let tm = textRe?.firstMatch(in: block, range: br2),
                  let tr = Range(tm.range(at: 1), in: block),
                  let cm = contentRe?.firstMatch(in: block, range: br2),
                  let cr = Range(cm.range(at: 1), in: block)
            else { return }

            let title = String(block[tr]).trimmingCharacters(in: .whitespacesAndNewlines)
            var src   = String(block[cr])
            if let h  = src.firstIndex(of: "#") { src = String(src[src.startIndex..<h]) }
            src = src.removingPercentEncoding ?? src

            if !title.isEmpty && !src.isEmpty {
                results.append((title, decode(src, relativeTo: tocBase)))
            }
        }
        return results
    }

    // ── Map TOC entries to char offsets ───────────────────────────────────────

    private static func mapToOffsets(
        _ entries: [(title: String, resolvedURL: URL)],
        pathToOffset: [String: Int]
    ) -> [(title: String, charOffset: Int)] {

        // Secondary lookup by filename (last path component) for resilience
        var nameToOffset: [String: Int] = [:]
        for (path, offset) in pathToOffset {
            nameToOffset[URL(fileURLWithPath: path).lastPathComponent] = offset
        }

        var seen  = Set<Int>()
        var result: [(title: String, charOffset: Int)] = []

        for entry in entries {
            let url    = entry.resolvedURL.standardized
            let offset = pathToOffset[url.path]
                      ?? nameToOffset[url.lastPathComponent]
            guard let offset, !seen.contains(offset) else { continue }
            seen.insert(offset)
            result.append((title: entry.title, charOffset: offset))
        }
        return result.sorted { $0.charOffset < $1.charOffset }
    }

    // =========================================================================
    // MARK: - EPUB helpers (OPF parsing, HTML files, text extraction)
    // =========================================================================

    private static func locateOPF(in dir: URL) -> URL? {
        let containerURL = dir.appendingPathComponent("META-INF/container.xml")
        guard let data = try? Data(contentsOf: containerURL),
              let xml = String(data: data, encoding: .utf8) else { return nil }
        guard let start = xml.range(of: "full-path=\"")?.upperBound,
              let end   = xml[start...].firstIndex(of: "\"") else { return nil }
        return dir.appendingPathComponent(String(xml[start..<end]))
    }

    private static func orderedHTMLFiles(opfURL: URL) -> [URL] {
        guard let data = try? Data(contentsOf: opfURL),
              let opf  = String(data: data, encoding: .utf8) else { return [] }
        let base = opfURL.deletingLastPathComponent()

        var manifest: [String: URL] = [:]
        if let re = try? NSRegularExpression(
            pattern: #"<item[^>]+\bid="([^"]+)"[^>]+\bhref="([^"]+)""#) {
            re.enumerateMatches(in: opf, range: nsRange(opf)) { m, _, _ in
                guard let m,
                      let ir = Range(m.range(at: 1), in: opf),
                      let hr = Range(m.range(at: 2), in: opf) else { return }
                let href = (String(opf[hr]).removingPercentEncoding ?? String(opf[hr]))
                manifest[String(opf[ir])] = base.appendingPathComponent(href)
            }
        }

        var ordered: [URL] = []
        if let re = try? NSRegularExpression(pattern: #"<itemref[^>]+\bidref="([^"]+)""#) {
            re.enumerateMatches(in: opf, range: nsRange(opf)) { m, _, _ in
                guard let m, let ir = Range(m.range(at: 1), in: opf) else { return }
                if let url = manifest[String(opf[ir])] { ordered.append(url) }
            }
        }
        return ordered
    }

    private static func allHTMLFiles(in dir: URL) -> [URL] {
        guard let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return (en.allObjects as? [URL] ?? [])
            .filter { ["html","xhtml","htm"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.path < $1.path }
    }

    private static func htmlToText(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType:      NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        if let as_ = try? NSAttributedString(data: data, options: opts, documentAttributes: nil) {
            return as_.string
        }
        if let s = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            return stripTags(s)
        }
        return nil
    }

    private static func stripTags(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "<style[\\s\\S]*?</style>",   with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "<(p|br|div|h[1-6]|li)[^>]*>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "")
        s = s.replacingOccurrences(of: "&amp;",  with: "&")
        s = s.replacingOccurrences(of: "&lt;",   with: "<")
        s = s.replacingOccurrences(of: "&gt;",   with: ">")
        s = s.replacingOccurrences(of: "&nbsp;|&#160;", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "&quot;", with: "\"")
        s = s.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // =========================================================================
    // MARK: - Tiny utilities
    // =========================================================================

    private static func nsRange(_ s: String) -> NSRange {
        NSRange(s.startIndex..., in: s)
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m  = re.firstMatch(in: text, range: nsRange(text)),
              let r  = Range(m.range(at: 1), in: text)
        else { return nil }
        return String(text[r])
    }

    private static func decode(_ href: String, relativeTo base: URL) -> URL {
        let pct = href.removingPercentEncoding ?? href
        return base.appendingPathComponent(pct).standardized
    }
}
