import Foundation

enum GeminiVoiceFailure: LocalizedError {
    case invalidEndpoint
    case unauthorized
    case rejected(Int, String)
    case connection

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            AppLocalization.text(LocalizedStringResource("Poki could not connect to Gemini Live."))
        case .unauthorized:
            AppLocalization.text(LocalizedStringResource("Check your Gemini key in Settings › Models. Gemini rejected it."))
        case .rejected(let code, let detail):
            code > 0
                ? AppLocalization.text(LocalizedStringResource("Gemini answered \(code): \(detail)"))
                : AppLocalization.text(LocalizedStringResource("Gemini answered: \(detail)"))
        case .connection:
            AppLocalization.text(LocalizedStringResource("Poki could not connect to Gemini Live."))
        }
    }

    static func redact(_ text: String) -> String {
        text.replacingOccurrences(of: #"AIza[\w-]+"#, with: "the API key", options: .regularExpression)
    }
}

@MainActor
final class GeminiVoiceAdapter: VoiceSocketAdapter {
    static let defaultModel = "gemini-3.8-live"
    static let endpoint = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

    private static let strippedSchemaKeys: Set<String> = [
        "$schema", "$defs", "definitions", "$id", "$ref", "$comment",
    ]

    private struct TurnState {
        var userSpeaking = false
        var interruptedTurn = false
        var userTranscript = ""
        var activeResponseID: String?
        var nextResponseSequence = 0
        var outputTranscript = ""
        var dropModelAudio = false
        var callNamesByID: [String: String] = [:]
        var emittedCallIDs: Set<String> = []
        var cancelledCallIDs: Set<String> = []
        var nextCallSequence = 0
        var pendingContextPrompt = false
        var pendingPCMInput = false
    }

    let model: String
    let instructions: String
    let tools: [[String: Any]]
    private var state = TurnState()

    init(model: String = GeminiVoiceAdapter.defaultModel,
         instructions: String,
         tools: [[String: Any]]) {
        self.model = model
        self.instructions = instructions
        self.tools = tools
    }

    /// The key goes in a header, as Google's SDK sends it, so no URL in an error or a log carries it.
    func makeRequest(secret: String) throws -> URLRequest {
        guard let url = URL(string: Self.liveURL) else { throw GeminiVoiceFailure.invalidEndpoint }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(secret, forHTTPHeaderField: "x-goog-api-key")
        return request
    }

    private static var liveURL: String {
        #if DEBUG && targetEnvironment(simulator)
        // Simulator runs only: `-pokiGeminiLiveURL ws://127.0.0.1:<port>` talks to a local stand-in for Gemini Live.
        if let local = UserDefaults.standard.string(forKey: "pokiGeminiLiveURL") { return local }
        #endif
        return endpoint
    }

    func setupPayload() -> [String: Any] {
        let modelPath = model.hasPrefix("models/") ? model : "models/\(model)"
        let declarations: [[String: Any]] = tools.compactMap { tool in
            guard let name = tool["name"] as? String,
                  let description = tool["description"] as? String else { return nil }
            // No behavior: each Live model runs calls its own way (3.8 Live without blocking, 3.1 Flash
            // Live blocking only), and a result is then said once the model is idle.
            var declaration: [String: Any] = ["name": name, "description": description]
            if let parameters = tool["parameters"] as? [String: Any] {
                declaration["parametersJsonSchema"] = Self.stripSchemaMeta(parameters)
            }
            return declaration
        }
        var setup: [String: Any] = [
            "model": modelPath,
            "generationConfig": ["responseModalities": ["AUDIO"]],
            "systemInstruction": ["parts": [["text": instructions]]],
            "inputAudioTranscription": [String: Any](),
            "outputAudioTranscription": [String: Any](),
        ]
        if !declarations.isEmpty {
            setup["tools"] = [["functionDeclarations": declarations]]
        }
        return ["setup": setup]
    }

    func handshake(send: (String) async throws -> Void,
                   receive: () async throws -> [String: Any]) async throws {
        let payload = try JSONSerialization.data(withJSONObject: setupPayload())
        try await send(String(decoding: payload, as: UTF8.self))
        while true {
            let message = try await receive()
            if message["setupComplete"] != nil {
                return
            }
            if let error = message["error"] as? [String: Any] {
                let code = error["code"] as? Int ?? 0
                let reason = GeminiVoiceFailure.redact(error["message"] as? String ?? "setup rejected")
                if code == 401 || code == 403 {
                    throw GeminiVoiceFailure.unauthorized
                }
                throw GeminiVoiceFailure.rejected(code, reason)
            }
        }
    }

    func encodeMicrophonePCM(_ pcm16LE: Data) -> [String: Any]? {
        [
            "realtimeInput": [
                "audio": [
                    "data": pcm16LE.base64EncodedString(),
                    "mimeType": "audio/pcm;rate=16000",
                ],
            ],
        ]
    }

    func translateClientEvent(_ event: [String: Any], controls: VoiceSocketControls) -> [[String: Any]] {
        guard let type = event["type"] as? String else { return [] }
        switch type {
        case "output_audio_buffer.clear":
            controls.clearPlayback()
            return []

        case "response.cancel":
            state.dropModelAudio = true
            state.outputTranscript = ""
            if let activeID = state.activeResponseID {
                state.activeResponseID = nil
                controls.emitEvent(["type": "response.done", "response": ["id": activeID]])
            }
            return []

        case "conversation.item.create":
            guard let item = event["item"] as? [String: Any],
                  let itemType = item["type"] as? String else { return [] }
            if itemType == "function_call_output" {
                let callID = item["call_id"] as? String ?? ""
                let output = item["output"] as? String ?? ""
                let name = state.callNamesByID[callID] ?? "do"
                if state.cancelledCallIDs.contains(callID) {
                    state.pendingContextPrompt = true
                    return [[
                        "clientContent": [
                            "turns": [["role": "user", "parts": [["text": "[Tool \(name) finished: \(output)]"]]]],
                            "turnComplete": false,
                        ],
                    ]]
                }
                state.pendingContextPrompt = false
                return [[
                    "toolResponse": [
                        "functionResponses": [[
                            "id": callID,
                            "name": name,
                            "response": ["result": output],
                        ]],
                    ],
                ]]
            }
            // TODO: unverified against a real key. Notes go out as clientContent with turnComplete false and
            // only complete on the next response.create; a note with no response.create after it (the
            // carry-over note at the start of a second talk, Stop talking) may leave Gemini waiting.
            if itemType == "message", let content = item["content"] as? [[String: Any]] {
                let audioFrames: [[String: Any]] = content.compactMap { part in
                    guard part["type"] as? String == "input_audio",
                          let encoded = part["audio"] as? String else { return nil }
                    return [
                        "realtimeInput": [
                            "audio": [
                                "data": encoded,
                                "mimeType": "audio/pcm;rate=24000",
                            ],
                        ],
                    ]
                }
                if !audioFrames.isEmpty {
                    state.pendingPCMInput = true
                    return audioFrames
                }
                let text = content.compactMap { part -> String? in
                    guard part["type"] as? String == "input_text" else { return nil }
                    return part["text"] as? String
                }.joined(separator: "\n")
                guard !text.isEmpty else { return [] }
                state.pendingContextPrompt = true
                return [[
                    "clientContent": [
                        "turns": [["role": "user", "parts": [["text": "[System note from Poki: \(text)]"]]]],
                        "turnComplete": false,
                    ],
                ]]
            }
            return []

        case "response.create":
            state.dropModelAudio = false
            if state.pendingPCMInput {
                state.pendingPCMInput = false
                return [["realtimeInput": ["audioStreamEnd": true]]]
            }
            if state.pendingContextPrompt {
                state.pendingContextPrompt = false
                return [["clientContent": ["turnComplete": true]]]
            }
            return []

        default:
            return []
        }
    }

    func translateServerMessage(_ message: [String: Any], controls: VoiceSocketControls) {
        if let cancel = message["toolCallCancellation"] as? [String: Any],
           let ids = cancel["ids"] as? [String] {
            state.cancelledCallIDs.formUnion(ids)
        }

        if let content = message["serverContent"] as? [String: Any] {
            handleServerContent(content, usage: message["usageMetadata"] as? [String: Any], controls: controls)
        }

        if let toolCall = message["toolCall"] as? [String: Any],
           let calls = toolCall["functionCalls"] as? [[String: Any]], !calls.isEmpty {
            handleFunctionCalls(calls, controls: controls)
        }

        if let error = message["error"] as? [String: Any] {
            let reason = GeminiVoiceFailure.redact(error["message"] as? String ?? "Gemini Live error")
            controls.emitEvent(["type": "error", "error": ["message": reason]])
        }
    }

    func mapConnectionError(_ error: Error, httpStatus: Int, closeCode: Int, closeReason: String) -> Error {
        if let known = error as? GeminiVoiceFailure { return known }
        let reason = GeminiVoiceFailure.redact(closeReason)
        // Gemini closes with 1007 and "API key not valid" for a wrong key, 1008 for a key without access.
        if httpStatus == 401 || httpStatus == 403 || closeCode == 1007 || closeCode == 1008 {
            return GeminiVoiceFailure.unauthorized
        }
        if !reason.isEmpty { return GeminiVoiceFailure.rejected(closeCode, reason) }
        if httpStatus >= 400 {
            return GeminiVoiceFailure.rejected(httpStatus, GeminiVoiceFailure.redact(error.localizedDescription))
        }
        if error is URLError { return error }
        return GeminiVoiceFailure.connection
    }

    private func handleServerContent(_ content: [String: Any], usage: [String: Any]?, controls: VoiceSocketControls) {
        if content["interrupted"] as? Bool == true {
            state.interruptedTurn = true
            flushOutputTranscript(controls: controls)
            // VoiceModel marks the talk interrupted only when speech_started arrives while phase is .speaking,
            // before output_audio_buffer.cleared moves the phase out of .speaking.
            controls.emitEvent(["type": "input_audio_buffer.speech_started"])
            controls.clearPlayback()
            state.userSpeaking = true
            state.dropModelAudio = false
            if let activeID = state.activeResponseID {
                state.activeResponseID = nil
                controls.emitEvent(["type": "response.done", "response": ["id": activeID]])
            }
        }

        // TODO: Gemini sends no speech-start event with automatic VAD, so the first transcription chunk
        // stands in for it; its latency against a real key is unmeasured.
        if let inputTrans = content["inputTranscription"] as? [String: Any],
           let chunk = inputTrans["text"] as? String, !chunk.isEmpty {
            if !state.userSpeaking, state.activeResponseID == nil {
                state.userSpeaking = true
                state.dropModelAudio = false
                controls.emitEvent(["type": "input_audio_buffer.speech_started"])
            }
            state.userTranscript += chunk
        }

        let parts = (content["modelTurn"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
        var audioChunks: [Data] = []
        var inlineCalls: [[String: Any]] = []
        for part in parts {
            if part["thought"] as? Bool == true { continue }
            if let inline = part["inlineData"] as? [String: Any],
               let mime = inline["mimeType"] as? String, mime.hasPrefix("audio/pcm"),
               let encoded = inline["data"] as? String,
               let pcm = Data(base64Encoded: encoded), !pcm.isEmpty {
                audioChunks.append(pcm)
            }
            if let call = part["functionCall"] as? [String: Any] {
                inlineCalls.append(call)
            }
        }

        let outputChunk = (content["outputTranscription"] as? [String: Any])?["text"] as? String ?? ""
        if (!audioChunks.isEmpty || !outputChunk.isEmpty), !state.dropModelAudio {
            finishUserSpeechIfNeeded(controls: controls)
            ensureActiveResponse(controls: controls)
            for pcm in audioChunks {
                controls.playPCM16LE(pcm)
            }
            if !outputChunk.isEmpty {
                state.outputTranscript += outputChunk
            }
        }

        if !inlineCalls.isEmpty {
            handleFunctionCalls(inlineCalls, controls: controls)
        }

        let generationComplete = content["generationComplete"] as? Bool == true
        let turnComplete = content["turnComplete"] as? Bool == true
        // An interrupted turn ends interrupted, then turnComplete, while the person is still talking: their
        // speech ends when the next answer starts.
        var userTurnWithoutAnswer = false
        if generationComplete || turnComplete, !state.interruptedTurn {
            userTurnWithoutAnswer = finishUserSpeechIfNeeded(controls: controls) && state.activeResponseID == nil
            if !state.dropModelAudio {
                flushOutputTranscript(controls: controls)
            } else {
                state.outputTranscript = ""
            }
        }

        // TODO: gemini-3.8-live-extended-thinking can send turnComplete with interactionStatus IN_PROGRESS
        // while it still reasons; that is read here as the end of the answer.
        if turnComplete {
            state.interruptedTurn = false
            state.dropModelAudio = false
            state.outputTranscript = ""
            // The model chose not to answer (proactive audio): an empty answer, so the talk can end in time.
            if userTurnWithoutAnswer { ensureActiveResponse(controls: controls) }
            if let activeID = state.activeResponseID {
                state.activeResponseID = nil
                var response: [String: Any] = ["id": activeID]
                if let mappedUsage = Self.mapUsage(usage) {
                    response["usage"] = mappedUsage
                }
                controls.emitEvent(["type": "response.done", "response": response])
            }
        }
    }

    private func handleFunctionCalls(_ calls: [[String: Any]], controls: VoiceSocketControls) {
        let fresh = calls.filter { call in
            guard let id = call["id"] as? String, !id.isEmpty else { return true }
            return !state.emittedCallIDs.contains(id)
        }
        guard !fresh.isEmpty else { return }

        state.dropModelAudio = false
        finishUserSpeechIfNeeded(controls: controls)
        flushOutputTranscript(controls: controls)
        let responseID = ensureActiveResponse(controls: controls)

        for call in fresh {
            guard let name = call["name"] as? String, !name.isEmpty else { continue }
            let callID: String
            if let provided = call["id"] as? String, !provided.isEmpty {
                callID = provided
            } else {
                state.nextCallSequence += 1
                callID = "gemini-call-\(state.nextCallSequence)"
            }
            state.emittedCallIDs.insert(callID)
            state.callNamesByID[callID] = name
            let args = call["args"] as? [String: Any] ?? [:]
            let arguments = (try? JSONSerialization.data(withJSONObject: args, options: [.sortedKeys]))
                .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
            controls.emitEvent([
                "type": "response.output_item.done",
                "item": [
                    "type": "function_call",
                    "call_id": callID,
                    "name": name,
                    "arguments": arguments,
                ],
            ])
        }

        state.activeResponseID = nil
        controls.emitEvent(["type": "response.done", "response": ["id": responseID]])
    }

    @discardableResult
    private func ensureActiveResponse(controls: VoiceSocketControls) -> String {
        if let existing = state.activeResponseID { return existing }
        state.nextResponseSequence += 1
        let id = "gemini-r\(state.nextResponseSequence)"
        state.activeResponseID = id
        controls.emitEvent(["type": "response.created", "response": ["id": id]])
        return id
    }

    /// Whether the person was speaking until now.
    @discardableResult
    private func finishUserSpeechIfNeeded(controls: VoiceSocketControls) -> Bool {
        let wasSpeaking = state.userSpeaking
        if wasSpeaking {
            state.userSpeaking = false
            controls.emitEvent(["type": "input_audio_buffer.speech_stopped"])
            controls.emitEvent(["type": "conversation.item.added", "item": ["role": "user"]])
        }
        let trimmed = state.userTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        state.userTranscript = ""
        if !trimmed.isEmpty {
            controls.emitEvent([
                "type": "conversation.item.input_audio_transcription.completed",
                "transcript": trimmed,
            ])
        }
        return wasSpeaking
    }

    private func flushOutputTranscript(controls: VoiceSocketControls) {
        let trimmed = state.outputTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        state.outputTranscript = ""
        if !trimmed.isEmpty {
            controls.emitEvent([
                "type": "response.output_audio_transcript.done",
                "transcript": trimmed,
            ])
        }
    }

    private static func stripSchemaMeta(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, child) in dict where !strippedSchemaKeys.contains(key) {
                out[key] = stripSchemaMeta(child)
            }
            return out
        }
        if let array = value as? [Any] {
            return array.map(stripSchemaMeta)
        }
        return value
    }

    private static func mapUsage(_ usage: [String: Any]?) -> [String: Any]? {
        guard let usage else { return nil }
        func tokens(in details: Any?, modality: String) -> Int {
            guard let items = details as? [[String: Any]] else { return 0 }
            return items.reduce(0) { sum, entry in
                (entry["modality"] as? String)?.uppercased() == modality
                    ? sum + (entry["tokenCount"] as? Int ?? 0)
                    : sum
            }
        }
        let promptDetails = usage["promptTokensDetails"]
        let responseDetails = usage["responseTokensDetails"]
        let textIn = tokens(in: promptDetails, modality: "TEXT")
        let audioIn = tokens(in: promptDetails, modality: "AUDIO")
        let textOut = tokens(in: responseDetails, modality: "TEXT")
        let audioOut = tokens(in: responseDetails, modality: "AUDIO")
        guard textIn + audioIn + textOut + audioOut > 0 else { return nil }
        return [
            "input_token_details": ["text_tokens": textIn, "audio_tokens": audioIn],
            "output_token_details": ["text_tokens": textOut, "audio_tokens": audioOut],
        ]
    }
}
