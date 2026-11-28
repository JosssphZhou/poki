#if POKI_WATCH
import Foundation
import Speech
import UIKit

enum WatchVoiceSpeechError: LocalizedError {
    case permission, unavailable, noSpeech, timedOut, unreadable, recognitionFailed

    var errorDescription: String? {
        switch self {
        case .permission: AppLocalization.text(LocalizedStringResource("Allow speech recognition for Poki on iPhone, then try again."))
        case .unavailable: AppLocalization.text(LocalizedStringResource("On-device speech recognition isn’t available for Poki’s language on iPhone."))
        case .noSpeech: AppLocalization.text(LocalizedStringResource("Poki didn’t hear a request. Hold the microphone and speak again."))
        case .timedOut: AppLocalization.text(LocalizedStringResource("Speech recognition timed out. Record a shorter request and try again."))
        case .unreadable: AppLocalization.text(LocalizedStringResource("Poki couldn’t open the Watch recording. Record the request again."))
        case .recognitionFailed: AppLocalization.text(LocalizedStringResource("iPhone couldn’t recognize the recording on-device. Try recording the request again."))
        }
    }
}

extension Dictation {
    static func transcribe(recording: Data) async throws -> String {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-pokiWatchVoiceTestTranscript") {
            return "Check whether Poki automation is on on this iPhone."
        }
        #endif
        let permission = SFSpeechRecognizer.authorizationStatus()
        if permission == .notDetermined, UIApplication.shared.applicationState == .active {
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
            guard granted else { throw WatchVoiceSpeechError.permission }
        } else if permission != .authorized {
            throw WatchVoiceSpeechError.permission
        }
        guard let recognizer = SFSpeechRecognizer(locale: AppLocalization.locale), recognizer.supportsOnDeviceRecognition else {
            throw WatchVoiceSpeechError.unavailable
        }
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".m4a")
        do {
            try recording.write(to: url, options: .completeFileProtection)
        } catch {
            throw WatchVoiceSpeechError.unreadable
        }
        defer { try? FileManager.default.removeItem(at: url) }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        let transcripts = Self.transcripts(recognizer, request: request)
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                for try await text in transcripts {
                    if !text.isEmpty { return text }
                }
                throw WatchVoiceSpeechError.noSpeech
            }
            group.addTask {
                try await Task.sleep(for: .seconds(25))
                throw WatchVoiceSpeechError.timedOut
            }
            defer { group.cancelAll() }
            guard let text = try await group.next() else { throw WatchVoiceSpeechError.noSpeech }
            return text
        }
    }

    nonisolated private static func transcripts(_ recognizer: SFSpeechRecognizer, request: SFSpeechURLRecognitionRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { stream in
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    stream.yield(result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines))
                    stream.finish()
                } else if error != nil {
                    stream.finish(throwing: WatchVoiceSpeechError.recognitionFailed)
                }
            }
            stream.onTermination = { _ in task.cancel() }
        }
    }
}
#endif
