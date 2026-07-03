import AppKit
import Combine

/// Renders document text to an audio file: NSSpeechSynthesizer writes AIFF,
/// then lame (or ffmpeg) encodes MP3. Machines with neither encoder get AAC
/// (.m4a) via the system's afconvert instead — macOS cannot encode MP3 natively.
final class AudioExporter: NSObject, ObservableObject, NSSpeechSynthesizerDelegate {

    enum ExportError: LocalizedError {
        case renderFailed
        case encodeFailed(String)

        var errorDescription: String? {
            switch self {
            case .renderFailed:          return "Speech rendering failed."
            case .encodeFailed(let msg): return "Audio encoding failed: \(msg)"
            }
        }
    }

    @Published var isExporting = false

    private var synth: NSSpeechSynthesizer?
    private var aiffURL: URL?
    private var destURL: URL?
    private var completion: ((Result<URL, Error>) -> Void)?

    private static let encoderPaths = [
        "/opt/homebrew/bin/lame", "/usr/local/bin/lame",
        "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg",
    ]

    /// True when an MP3 encoder is installed; otherwise exports fall back to .m4a.
    static var mp3EncoderAvailable: Bool {
        encoderPaths.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func export(text: String,
                voice: NSSpeechSynthesizer.VoiceName?,
                rate: Float,
                to dest: URL,
                completion: @escaping (Result<URL, Error>) -> Void) {
        guard !isExporting else { return }
        isExporting = true
        self.destURL = dest
        self.completion = completion

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("StorytellerExport_\(UUID().uuidString).aiff")
        aiffURL = tmp

        let s = NSSpeechSynthesizer()
        if let voice { s.setVoice(voice) }
        s.rate = 180.0 * rate
        s.delegate = self
        synth = s

        // Renders offline (faster than real time); delegate fires when done.
        if !s.startSpeaking(text, to: tmp) {
            finish(.failure(ExportError.renderFailed))
        }
    }

    func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        guard let aiff = aiffURL, let dest = destURL else { return }
        guard finishedSpeaking,
              FileManager.default.fileExists(atPath: aiff.path) else {
            finish(.failure(ExportError.renderFailed))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try Self.encode(aiff: aiff, to: dest)
                try? FileManager.default.removeItem(at: aiff)
                self.finish(.success(dest))
            } catch {
                try? FileManager.default.removeItem(at: aiff)
                self.finish(.failure(error))
            }
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isExporting = false
            self.synth = nil
            self.completion?(result)
            self.completion = nil
        }
    }

    // MARK: - Encoding

    private static func encode(aiff: URL, to dest: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: dest)

        if dest.pathExtension.lowercased() == "m4a" {
            try run("/usr/bin/afconvert",
                    ["-f", "m4af", "-d", "aac", aiff.path, dest.path])
            return
        }
        if let lame = ["/opt/homebrew/bin/lame", "/usr/local/bin/lame"]
            .first(where: { fm.isExecutableFile(atPath: $0) }) {
            try run(lame, ["-V2", "--quiet", aiff.path, dest.path])
            return
        }
        if let ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
            .first(where: { fm.isExecutableFile(atPath: $0) }) {
            try run(ffmpeg, ["-y", "-loglevel", "error", "-i", aiff.path,
                             "-codec:a", "libmp3lame", "-qscale:a", "2", dest.path])
            return
        }
        // No MP3 encoder — produce AAC beside the requested name.
        let m4a = dest.deletingPathExtension().appendingPathExtension("m4a")
        try? fm.removeItem(at: m4a)
        try run("/usr/bin/afconvert", ["-f", "m4af", "-d", "aac", aiff.path, m4a.path])
    }

    private static func run(_ launchPath: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let errPipe = Pipe()
        p.standardError = errPipe
        p.standardOutput = Pipe()
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? ""
            throw ExportError.encodeFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
