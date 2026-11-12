# Proposal: pause and resume, the talk card, and the open microphone

Three things from the app redesign that are **not** part of the SwiftUI rebuild. Each needs changes below the
interface, so they are proposed here on their own. The prototype in `design/app-prototype` shows how each
would look.

Paths are under `native/`. Line references are to `main` at 291a904. Points marked *to confirm* are my reading
of the code and have not been tested.

## 1. Pause and resume

### What the owner gets

While Poki or an outside agent works, the Dynamic Island shows the action in hand and one button. Today that
button is Stop, which ends the task. The proposal: the button **pauses** the task where it is, the island
stays, and the same button **resumes** it.

### What happens today

- The island's button is `StopRunnerIntent` (`ios-app/Shared/ApprovalIntents.swift:76`). It posts a
  notification that `AppModel` answers with `pauseRunner(reason:)` (`ios-app/Poki/App/AppModel.swift:953`,
  `:1334`): the runner stops, and the next request from an agent starts it again. The task is not told.
- So today's Stop neither ends a task cleanly nor holds it: the agent's next action simply wakes the runner.
- The chat's own Stop, `ChatModel.stop()` (`ios-app/Poki/Chat/ChatModel.swift:340`), does end the task: it sets
  `stopAsked`, and the loop answers every remaining tool call with "Task stopped. Action not executed." That
  task cannot be picked up again.
- The app already has one state where a task waits and then goes on: the **hand-off** ("Your turn"). PokiCore
  refuses input while it is open, the agent keeps polling `look`, and `HandoffDoneIntent` ends it
  (`ios/PokiCore/Sources/PokiCore/Computer.swift:371-383`, `Core.swift:221-223`, `Core.swift:348`).

### Proposed solution

Treat a pause as a hand-off that the owner starts.

1. **PokiCore enforces it.** Add `pause()` and `resume()` next to `handoffDone(id:)`. While paused, `do` returns
   at once with a plain, non-error result ("Paused by the owner. Poll `look` until it says the task may go
   on."), exactly as a hand-off does, and `look` reports `paused: true`. The rule lives in PokiCore, so it holds
   for every agent whether or not its model cooperates. It returns at once instead of blocking because an MCP
   client gives up on a call after about a minute.
2. **Events.** Two new `ShellEvent` cases, `paused` and `resumed`, beside `handoffRequested` and `handoffEnded`.
3. **Poki's own loop.** `ChatModel.run` checks a gate before each model turn and before each tool call. The
   action under way finishes; nothing more is sent to the phone or the model until the gate opens. On resume
   the loop adds one line for the model: "The owner paused for N seconds. The screen may have changed; look
   again before acting."
4. **Live Activity.** A new `Phase.paused` in `PokiActivityAttributes.ContentState`
   (`ios-app/Shared/PokiActivityAttributes.swift:16`), and two intents, `PauseIntent` and `ResumeIntent`,
   written like `HandoffDoneIntent`. `ActivityFace` gets a paused face: Poki at rest, the word "Paused", the
   Resume button.
5. **Timers.** `ActivityController` must not call a paused run finished (`armFinish`, 15 s of quiet) or stale
   (10 minutes). Both stop while paused and start again on resume.

### Decisions for the owner

| Question | Suggested answer |
| --- | --- |
| Does Stop stay? | Yes, as a second action in the expanded island and in the chat. Pause alone leaves no way to end a task. |
| How long may a task stay paused? | 10 minutes, then it ends as "Stopped" and the chat says so. A task left paused forever holds the runner. |
| Can you pause while an approval is waiting? | No. The approval already holds the task and has its own clock. |
| What about a pause in the middle of typing? | The action under way always finishes, so a field is never left half typed. |

### Size and risk

- Touches PokiCore, the Live Activity (app and widget extension), `AppModel`, `ChatModel` and the strings.
- Main risk: an outside agent that ignores "paused" and gives up. It cannot act, because PokiCore refuses, but
  its task fails. The message has to tell it to keep polling, as the hand-off message does.
- Tests: `PokiTests/ChatHarnessTests.swift` for the gate and the resume line; a PokiCore test that `do` is
  refused while paused; `scripts/mock-model.py` for a paused run end to end.

## 2. The talk card

### What the owner gets

After a live voice conversation, the chat keeps a card instead of a transcript: how long the talk was, and what
came of it (an answer, a change Poki made, a reminder it set). The conversation itself is not kept.

### What happens today

- A live conversation runs in `VoiceModel` (`ios-app/Poki/Voice/VoiceModel.swift`) and collects `VoiceLine`s
  with a role: you, Poki, tool or note (`VoiceModel.swift:169`).
- When it ends, every line is written into the chat as ordinary entries: `ChatModel.appendVoice`
  (`ChatModel.swift:120`) through `SessionStore.entries(voice:started:)`. So the chat keeps the whole
  conversation.
- Nothing in the app knows what a talk "came to".

### Proposed solution

1. **Let the model say what was settled.** Add one tool to the live session, `note_outcome({ title, detail,
   kind })` with `kind` one of `answer` or `action`. The model calls it each time something is settled. This
   also gives the live list the prototype shows under Poki's words. A phone task run during the talk adds its
   own outcome from `finish_task`, with no model call.
2. **A new chat entry.** `ChatEntry.Kind.talk(TalkRecord)`, where `TalkRecord` holds the start, the length and
   the outcomes. `appendVoice` writes this one entry instead of the lines. A talk with no outcomes writes a card
   that says nothing came of it.
3. **A setting, not a silent change.** Dropping the transcript changes what the app remembers. Suggested:
   Settings › Model › Voice › "Keep the words of a talk", off by default, for people who want today's behaviour.
4. **Storage.** `ChatEntry.Kind` is `Codable` and saved with each session. An older build that meets the new
   case must skip that entry instead of failing to read the session. *To confirm* in `SessionStore`'s decoding
   before this ships; if it fails today, the fix belongs in the same change.
5. **The sessions list.** Its preview line switches on the entry kind (`SessionStore.swift:53`); a talk shows
   its outcomes there.

### Decisions for the owner

| Question | Suggested answer |
| --- | --- |
| Is the transcript dropped by default? | Yes, with the setting above to keep it. |
| What if the model never calls `note_outcome`? | The card says nothing came of the talk. No second model call to summarise: it costs time and money after the person has hung up. |
| Does the approval classifier still see the talk? | Yes. It reads `voice.lines` while the talk is live; only what is saved afterwards changes. |
| A phone task during a talk: where is its record? | Directly after the talk card, as the same card every phone task leaves. |

### Size and risk

- Touches `VoiceModel`, `VoiceDirect` and `VoiceLink` (the tool), `ChatModel`, `SessionStore`, one new view, the
  strings.
- Main risk: the Realtime model calling `note_outcome` too often or not at all. It needs a short, firm
  instruction and a few recorded talks to tune against.
- Tests: `PokiTests/VoiceModelTests.swift` for the tool and the record; a decoding test for a session saved by
  the new build and read by the old shape.

## 3. Going on with a talk from another app

### What the owner gets

During a talk, Poki goes off to another app to do a step, says the answer, and the owner can say the next
thing from where they are, without going back to Poki.

### What happens today

- While a step runs in the background the microphone stays open. Once the answer has been said, the talk ends
  at once (`VoiceModel.endIfDone`): in front it would wait 8 seconds for the owner to go on.
- `PokiTests/VoiceModelTests.swift` holds this as intended (`testInTheBackgroundPokiStopsListeningUnlessAStepIsRunning`).
- The redesign does not change it. The Live Activity now shows the open microphone during a talk and has a
  button that ends it (`EndTalkIntent`), which is what makes a longer open microphone safe to offer.

### Proposed solution

When it is Poki’s own step that took the app to the background, keep the 8 seconds after the answer there too.
When the owner left Poki themself, end at once as today.

### Decisions for the owner

- Whether the microphone may stay open in the background after an answer at all.
- If so, whether 8 seconds is the right wait there, or the talk stays open until it is ended on the island.

### Size and risk

- One flag in `VoiceModel` and a change to four tests. I built it once and took it out again, because it
  changes what those tests promise.
- Main risk: an open microphone the owner did not expect. The island’s indicator and button are the answer to that.

## Order

Pause and resume first. It is the smaller change, it is enforced in one place, and it makes the island's one
button safe to press. The talk card and the open microphone can follow at any time; nothing else waits on them.
