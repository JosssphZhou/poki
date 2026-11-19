import AVFoundation
import Foundation
import Speech

/// Voice without the Mac's voice bridge.
///
/// - With the owner's OpenAI API key on this iPhone, Poki asks OpenAI for a one-minute Realtime key
///   itself (what `bin/voice-bridge.mjs` does on the Mac: the same model, instructions and tools). The
///   voice model listens, speaks and can read the screen (look); work on the phone goes to Poki's chat
///   agent (`VoiceTasks`).
/// - With any other model (a ChatGPT plan, Anthropic, OpenRouter…), whose sign-in has no Realtime
///   audio, holding the button dictates on this iPhone (Apple's speech recognition, on the device when
///   it can) and lets go to send it to Poki's chat; Poki reads the answer out loud.
enum VoiceDirect {
    /// The live voice model the owner picked (Accounts › OpenAI › Live Voice), GPT Realtime 2.1 by default.
    static var model: String { ModelCatalog.voiceModel }

    /// The OpenAI API key on this iPhone, when there is one.
    static var apiKey: String? { enabled ? ModelKeys.key(.openai) : nil }

    /// The owner's switch in Accounts › OpenAI › Live Voice (on unless turned off).
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "voice.openai.enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "voice.openai.enabled"); ModelKeys.saved += 1 }
    }

    /// Dictation into the chat works with any model the chat can use.
    static var canDictate: Bool { ModelKeys.hasUsableKey }

    /// The iPhone's language ("zh-Hans-CN"): the live voice hears and speaks it, whatever language Poki's
    /// own screens are in (the owner, 2026-11-19: to talk English, the iPhone is set to English).
    static var systemLanguage: String { Locale.preferredLanguages.first ?? "en" }

    /// The iPhone's language named in English ("Chinese, Simplified (China)").
    private static var language: String {
        Locale(identifier: "en").localizedString(forIdentifier: systemLanguage) ?? "English"
    }

    // Tuned against gpt-realtime-2.1 with spoken Chinese and stubbed tools (scripts/voice-eval.py). The
    // text before let a short English sound as the talk opened turn it to English, and read 稍微翻一下
    // (scroll a little) as "translate".
    private static var instructions: String { """
    # Role
    You are Poki, a voice assistant on the user's iPhone. You listen and speak; Poki's agent does the work on the phone.

    # Language
    - Speak \(language), the iPhone's language, from your first sentence to your last.
    - Never change language on your own: not for tool results, screen text, screenshots or notes from Poki in another language, not for a short sound, a word or a name in another language, and not for audio you could not make out. Change only when the user asks you to speak another language.
    - Translate only when the user asks for a translation.

    # Short sounds and unclear audio
    - When the latest audio holds no request (a filler or backchannel such as 嗯, 哦, 啊, uh-huh or ok, a cough, noise, or a word cut off as the talk opens), call wait_for_user and say nothing.
    - When the user clearly spoke to you but you could not make out the request, ask in one short sentence what they want, and do nothing until they answer. Never act on a guess.
    - When a request leaves out what it is about (帮我打开 with no app named, 发给他 with nobody named), ask for that one thing in a few words (打开哪个？) and call no tool. Never fill it in from earlier in the talk.

    # Replies
    - A clear request to do something on the phone: first say only "好" ("OK" in English), one word and nothing after it (never "好，我来帮你打开" or "好，我帮你往下翻"), then call the tool in the same turn. A question about the screen gets no such word: call look at once.
    - A request that sends something to someone (a message, a file, an email): first say in one short sentence what you will send to whom ("我把 hello 发给文件传输助手"), then call run_task in the same turn. Do not wait for the user to confirm; they can say stop.
    - After you call run_task, say nothing until its result arrives: no "我来处理", no "稍等", no "已经加到任务里", no "正在处理中". Its progress shows on the phone. Say how it is going only when the user asks.
    - When it is done, say the result in one short sentence; once an app is open, say that it is open ("微信打开了").
    - When the user says stop (停, 别说了, stop) at any time: stop talking, and call stop_task at once when a task is running.
    - Do not describe what you did or what else is on the screen, and add no greetings, filler or offers of more help. Explain only when the user asks.

    \(taskRules)
    """ }

    /// The model's way to end a turn without speaking (a 嗯, a cough): VoiceModel closes the call and asks
    /// for no answer after it.
    static let waitForUser = "wait_for_user"

    /// How the voice model works with Poki's agent (the Tools and Approvals sections); the Mac's voice bridge says the same.
    static let taskRules = """
    # Tools
    - Never guess facts about the phone. To say what is on the screen right now, call look. A screenshot of the screen follows each look answer as an image: use it with the numbered elements to say what is on the screen. Asked what is on the screen, name the app and its main content in one sentence, without listing buttons.
    - To open an app and do nothing more in it, call open_app with its name: it opens at once.
    - To scroll the screen in front (往下翻, 往上翻, 下一页), go back one page (返回, 返回上一页) or go to the Home Screen (回到桌面, 回主屏幕), call phone_step: it is done at once.
    - To do anything else on the phone (tap, type, send, change a setting, find or read something in an app, go to an app's own first page, open an app and do something in it), call run_task at once with the whole request. Poki's agent does every step and answers with how it ended. Never repeat a task that already ran, including tasks from before a reconnect that the conversation says have finished.
    - Short commands are phone actions too: 往下翻, 翻一下 and 下一页 mean scroll. When you hear 翻译 with no language named and nothing to translate, the user said 翻 (scroll).
    - While a task runs: when the user adds to it or changes it, call run_task with only what they added; it goes to the running task. When they ask how it is going (到哪了), call check_task and say where it is in one sentence. When they tell you to stop or cancel it, call stop_task at once.
    - Poki's agent can open and operate every app installed on this iPhone, Apple's and anyone else's (WeChat, Instagram, Uber, a bank, a game): never tell the user an app is out of reach before a task has tried.

    # Approvals and stopping
    - A step that sends, pays, deletes or calls waits until the user allows it on the phone; if the result says they did not, say so in one sentence and do not try another way.
    - Only the user approves, with their own finger: never ask for a task that opens Poki to tap Allow, Deny or anything else in it.
    """

    private static let empty: [String: Any] = ["type": "object", "properties": [String: Any](), "additionalProperties": false]
    private static let tools: [[String: Any]] = [
        ["type": "function", "name": waitForUser, "description": "End your turn without speaking, when the latest audio needs no answer: a filler or backchannel such as 嗯 or uh-huh, a cough, noise, or speech not meant for you.", "parameters": empty],
        ["type": "function", "name": "get_ios_version", "description": "Read the iPhone model and its iOS version. Changes nothing on the phone.", "parameters": empty],
        ["type": "function", "name": "look", "description": "Read the iPhone screen now: the app in front, its numbered elements (role, label, frame in points) and a screenshot. Changes nothing.", "parameters": empty],
        ["type": "function", "name": "open_app", "description": "Open one app on the iPhone by the name the user said (微信, Settings, 支付宝), and do nothing more in it. It opens in a few seconds, without Poki's agent. Before it say only 好, one word, and nothing else.",
         "parameters": ["type": "object", "properties": ["app": ["type": "string", "description": "The app's name as the user said it."]], "required": ["app"], "additionalProperties": false]],
        ["type": "function", "name": VoiceApps.step, "description": "One gesture on the screen in front, without Poki's agent: scroll_down (往下翻), scroll_up (往上翻), back (返回上一页) or home (回到桌面). Done in a second or two; the answer says what is on the screen after it. Before it say only 好, one word, and nothing else.",
         "parameters": ["type": "object", "properties": ["step": ["type": "string", "enum": VoiceApps.steps.keys.sorted()]], "required": ["step"], "additionalProperties": false]],
    ] + VoiceTasks.tools

    /// The tools the phone answers itself (the bridge runs none of them).
    static let localTools = tools.compactMap { $0["name"] as? String }

    /// The Realtime session Poki opens: model, instructions, voice, turn detection and tools.
    static var session: [String: Any] {
        [
            "type": "realtime", "model": model, "instructions": instructions, "output_modalities": ["audio"],
            "audio": [
                "input": ["turn_detection": ["type": "server_vad", "silence_duration_ms": 450, "prefix_padding_ms": 300, "threshold": 0.5, "create_response": true, "interrupt_response": true],
                          "noise_reduction": ["type": "near_field"], "transcription": transcription(systemLanguage)],
                "output": ["voice": "marin"],
            ],
            "tools": tools, "tool_choice": "auto", "parallel_tool_calls": false, "reasoning": ["effort": "low"],
        ]
    }

    /// How the person's speech is written into the talk (the model hears the audio itself): gpt-transcribe,
    /// told the iPhone's language, and English for the English words in it (app names, "hello"). Without a
    /// language, gpt-4o-mini-transcribe wrote a 嗯 as 안, n or 按.
    static func transcription(_ language: String) -> [String: Any] {
        let main = Locale(identifier: language).language.languageCode?.identifier ?? "en"
        return ["model": "gpt-transcribe", "languages": main == "en" ? ["en"] : [main, "en"], "prompt": transcriptionPrompt]
    }

    static let transcriptionPrompt = "Someone talking to Poki, a voice assistant, to use their iPhone: opening apps, scrolling, tapping, reading the screen."

    /// A one-minute Realtime key from OpenAI, made with the owner's API key (sent only to OpenAI).
    static func token(apiKey: String) async throws -> VoiceBridge.Token {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/realtime/client_secrets")!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["expires_after": ["anchor": "created_at", "seconds": 60], "session": session])
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status), let value = json?["value"] as? String else {
            // OpenAI echoes a masked key in some errors; keep even that out of the screen and the log.
            let message = ((json?["error"] as? [String: Any])?["message"] as? String ?? "client_secrets \(status)")
                .replacingOccurrences(of: #"sk-[\w*-]+"#, with: "the API key", options: .regularExpression)
            throw VoiceError.realtime(status, message)
        }
        return VoiceBridge.Token(value: value, model: model, local_tools: localTools)
    }
}

/// Hold to dictate, let go to send to Poki's chat, hear the answer: voice for models without Realtime.
@MainActor
final class Dictation: NSObject, AVSpeechSynthesizerDelegate {
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private let speaker = AVSpeechSynthesizer()
    private(set) var heard = ""
    var onHeard: ((String) -> Void)?
    var onSpoken: (() -> Void)?

    override init() {
        super.init()
        speaker.delegate = self
    }

    static func allowed() async -> Bool {
        let speech = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        let microphone = await AVAudioApplication.requestRecordPermission()
        return speech && microphone
    }

    func listen() throws {
        speaker.stopSpeaking(at: .immediate)
        heard = ""
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else { throw VoiceError.realtime(0, AppLocalization.text(LocalizedStringResource("Speech recognition is not available right now."))) }
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
        try audio.setActive(true)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        Self.tap(input, into: request)
        engine.prepare()
        try engine.start()
        recognition = Self.recognize(recognizer, request) { [weak self] text in
            self?.heard = text
            self?.onHeard?(text)
        }
    }

    // The audio tap and the recognizer call back on their own threads, so their blocks are made outside
    // the main actor.
    nonisolated private static func tap(_ input: AVAudioInputNode, into request: SFSpeechAudioBufferRecognitionRequest) {
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in request.append(buffer) }
    }

    nonisolated private static func recognize(_ recognizer: SFSpeechRecognizer, _ request: SFSpeechAudioBufferRecognitionRequest,
                                              heard: @escaping @MainActor (String) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, _ in
            guard let text = result?.bestTranscription.formattedString else { return }
            Task { @MainActor in heard(text) }
        }
    }

    /// Stops listening; the words heard so far (a moment later, for the last ones).
    func finish() async -> String {
        request?.endAudio()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        try? await Task.sleep(for: .milliseconds(600))
        recognition?.cancel()
        recognition = nil
        request = nil
        return heard.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        speaker.speak(utterance)
    }

    func stopSpeaking() { speaker.stopSpeaking(at: .immediate) }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onSpoken?() }
    }
}
