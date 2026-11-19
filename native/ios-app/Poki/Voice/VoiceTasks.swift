import Foundation

/// The live voice model's work on the phone. It listens and speaks; the steps on the phone are Poki's
/// chat agent's, the same model, harness, approvals and Live Activity as a typed message (the owner,
/// 2026-11-19). The voice model hands a task over (`run_task`), asks how it is going (`check_task`) and
/// stops it (`stop_task`); it has no tool that taps, swipes or types.
struct VoiceTasks {
    static let run = "run_task"
    static let check = "check_task"
    static let stop = "stop_task"
    static let names: Set<String> = [run, check, stop]
    /// How a run_task answer that went to the running task begins (VoiceModel asks for no answer after it).
    static let added = "added:"

    /// Answers one of `names` for the voice model: the text it reads, and whether the call failed. A
    /// `run_task` answer comes when the task has ended, so the talk keeps the call running until then.
    let call: @MainActor (_ name: String, _ arguments: String) async -> (text: String, failed: Bool)

    private static let notReady = (text: "error: Poki's chat is not ready; nothing was done", failed: true)

    /// Poki's own chat (`AskPoki.chat` in the app), the one the talk is held in and goes into when it ends.
    static func chat(_ chat: @escaping @MainActor () -> ChatModel?) -> VoiceTasks {
        VoiceTasks { name, arguments in await answer(name, arguments, in: chat()) }
    }

    @MainActor private static func answer(_ name: String, _ arguments: String, in chat: ChatModel?) async -> (text: String, failed: Bool) {
        guard let chat else { return notReady }
        switch name {
        case run:
            let args = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any]
            let task = args?["task"] as? String ?? ""
            guard chat.running else { return await chat.runSpoken(task) }
            return chat.addSpoken(task)
                ? ("\(added) the running task takes this in. Do not hand it over again; the task's result follows when it ends.", false)
                : ("busy: Poki is working on another task that cannot take additions; nothing was started. Say so, or stop it first.", true)
        case check:
            return (chat.spokenProgress, false)
        default:
            return chat.stopSpoken()
                ? ("stopping: the task is being stopped. Do not start it again unless the user asks.", false)
                : ("nothing to stop: Poki is not working on a task.", false)
        }
    }

    private static let empty: [String: Any] = ["type": "object", "properties": [String: Any](), "additionalProperties": false]

    /// The Realtime function definitions of `names`.
    static let tools: [[String: Any]] = [
        ["type": "function", "name": run,
         "description": "Hand one task on the iPhone to Poki's agent, which does every step (opens apps, taps, types, reads) and answers with how it ended. It can take from a few seconds to a few minutes; the user can talk meanwhile. While a task runs, a second run_task adds to that task instead of starting another. Before it say only 好, one word, and nothing else; only a task that sends something gets the one sentence that says what it sends to whom.",
         "parameters": ["type": "object", "properties": ["task": ["type": "string", "description": "What to do, in the user's own language and plain words, as you would ask a person. Include every detail the user gave (names, the exact text to type or send). Poki's agent hears nothing else of this conversation."]],
                        "required": ["task"], "additionalProperties": false]],
        ["type": "function", "name": check, "description": "Say how the task Poki's agent is doing is going: how long it has run, its plan and the step under way, and whether it waits for the user to allow something on the phone. Changes nothing.", "parameters": empty],
        ["type": "function", "name": stop, "description": "Stop the task Poki's agent is doing. The action the phone is in the middle of finishes; nothing more is done.", "parameters": empty],
    ]
}
