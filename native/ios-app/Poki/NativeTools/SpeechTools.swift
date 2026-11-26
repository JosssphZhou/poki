import AVFoundation
import Foundation
import UIKit
import PokiCore

/// Reads an article aloud with AVSpeechSynthesizer. The text comes from Poki's own browser (the page's
/// main text, captured with its URL and title) or from `text`. Long articles are spoken in chunks; the
/// page's URL and title are checked between chunks, so a page that changed is not read on as if it
/// were the same article. Only one reading runs at a time, and `action: stop` stops it.
enum SpeechTools {
    static let specs: [ToolSpec] = [
        .make("read_aloud",
              "Read an article aloud. action start (default) reads the current page in Poki's browser, or the text passed in text. The page's URL and title are checked between chunks; if the page changes, reading stops. action stop stops the current reading.",
              [
                "action": ["type": "string", "enum": ["start", "stop"]],
                "text": ["type": "string", "description": "The article text; omit to read the current Poki browser page."],
                "rate": ["type": "number", "minimum": 0.1, "maximum": 1.0, "description": "Speech rate; 0.5 is the system default."],
              ], []),
    ]

    @MainActor private static let reader = SpeechReader.shared

    @MainActor static func perform(_ arguments: String) async -> PokiCore.ToolAnswer {
        let args = ToolArgs(arguments)
        let action = (args.string("action") ?? "start").lowercased()
        if action == "stop" {
            let wasReading = reader.isReading
            reader.stop()
            return NativeToolAnswer.ok(wasReading ? "stopped: reading aloud stopped." : "stopped: nothing was being read aloud.")
        }
        guard action == "start" else {
            return NativeToolAnswer.invalid("action must be start or stop; nothing was read")
        }
        if reader.isReading {
            return NativeToolAnswer.ambiguous("something is already being read aloud. Ask the owner whether to stop it first, or call read_aloud with action stop; nothing new was started.")
        }
        let source: SpeechReader.Source
        if let text = args.string("text"), !text.isEmpty {
            guard text.count <= 100_000 else {
                return NativeToolAnswer.invalid("text is longer than 100,000 characters; nothing was read. Pass an article text or read a page.")
            }
            source = .text(title: nil, url: nil, body: text)
        } else {
            let browser = PokiBrowser.shared
            guard browser.isOpen, let url = browser.url else {
                return NativeToolAnswer.empty("nothing is open in Poki's browser. Open the article with web_open, or pass its text; nothing was read.")
            }
            let title = browser.title
            let body: String
            do {
                body = try await browser.call("return (document.body && document.body.innerText) || ''") as? String ?? ""
            } catch {
                return NativeToolAnswer.failed("the page's text could not be read: \(error.localizedDescription)")
            }
            let clean = body.replacingOccurrences(of: #"\n\s*\n\s*\n"#, with: "\n\n", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard clean.count >= 20 else {
                return NativeToolAnswer.empty("the page did not give enough visible text to read; nothing was read.")
            }
            source = .browser(title: title, url: url, body: clean)
        }
        let rate = Float(min(1.0, max(0.1, args.double("rate") ?? 0.5)))
        let started = reader.start(source, rate: rate)
        guard started else {
            return NativeToolAnswer.unavailable("the speech synthesizer could not start on this iPhone; nothing was read.")
        }
        let title = source.title.map { "“\($0)”" } ?? "the text"
        return NativeToolAnswer.ok("reading: \(title), \(source.body.count) characters. It continues after this task finishes; call read_aloud with action stop to stop it.")
    }
}

/// One reading at a time. The synthesizer keeps the owner's audio session and the page identity is
/// checked after each chunk, so a navigation cannot silently continue an article under a new page.
@MainActor
final class SpeechReader: NSObject, AVSpeechSynthesizerDelegate {
    enum Source {
        case browser(title: String?, url: URL, body: String)
        case text(title: String?, url: URL?, body: String)

        var title: String? {
            switch self {
            case .browser(let title, _, _), .text(let title, _, _): return title
            }
        }
        var body: String {
            switch self {
            case .browser(_, _, let body), .text(_, _, let body): return body
            }
        }
    }

    static let shared = SpeechReader()
    private let synthesizer = AVSpeechSynthesizer()
    private(set) var isReading = false
    private var chunks: [String] = []
    private var next = 0
    private var identity: (url: URL?, title: String?)?
    private var rate: Float = 0.5
    private var stopped = false

    override private init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = false
    }

    func start(_ source: Source, rate: Float) -> Bool {
        let body = source.body
        guard !body.isEmpty else { return false }
        chunks = Self.chunks(of: body)
        next = 0
        stopped = false
        self.rate = rate
        sourceIdentity = source
        switch source {
        case .browser(let title, let url, _): identity = (url, title)
        case .text(let title, let url, _): identity = (url, title)
        }
        isReading = true
        speakNext()
        return true
    }

    func stop() {
        stopped = true
        isReading = false
        chunks = []
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func speakNext() {
        guard !stopped, isReading else { return }
        guard next < chunks.count else {
            isReading = false
            return
        }
        let utterance = AVSpeechUtterance(string: chunks[next])
        utterance.rate = rate
        utterance.voice = Self.voice(for: chunks[next])
        next += 1
        synthesizer.speak(utterance)
    }

    private func pageChanged() -> Bool {
        guard case .browser(_, let url, _)? = sourceIdentity, let identity else { return false }
        let browser = PokiBrowser.shared
        return !browser.isOpen || browser.url?.absoluteString != url.absoluteString || browser.title != identity.title
    }

    /// The identity of the current source; for passed-in text there is no page to check.
    private var sourceIdentity: Source?

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard !self.stopped, self.isReading else { return }
            if self.pageChanged() {
                self.stop()
                AppLog.shared.add("speech", "the page changed while reading; stopped")
                return
            }
            self.speakNext()
        }
    }

    private static func voice(for text: String) -> AVSpeechSynthesisVoice? {
        let han = text.range(of: #"\p{Script=Han}"#, options: .regularExpression) != nil
        let language = han ? "zh-CN" : (Locale.current.language.languageCode?.identifier ?? "en")
        return AVSpeechSynthesisVoice(language: language) ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    private static func chunks(of text: String, limit: Int = 1200) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var chunks: [String] = []
        var current = ""
        for paragraph in normalized.components(separatedBy: "\n") {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if current.count + trimmed.count + 1 <= limit {
                current += (current.isEmpty ? "" : "\n") + trimmed
                continue
            }
            if !current.isEmpty { chunks.append(current); current = "" }
            var remaining = trimmed
            while remaining.count > limit {
                let cut = remaining.index(remaining.startIndex, offsetBy: limit)
                // Prefer a sentence end before the hard cut.
                let prefix = remaining[..<cut]
                if let last = prefix.lastIndex(where: { ".!?。！？".contains($0) }), prefix.distance(from: prefix.startIndex, to: last) > limit / 2 {
                    let end = remaining.index(after: last)
                    chunks.append(String(remaining[..<end]))
                    remaining = String(remaining[end...]).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    chunks.append(String(prefix))
                    remaining = String(remaining[cut...]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            current = remaining
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
