# Poki app prototype

A clickable prototype of a redesigned Poki iPhone app. It runs in a browser, needs no build and has no
dependencies. It is a design reference: the app itself is SwiftUI (`native/ios-app`), and nothing here ships in it.

## Run it

```sh
python3 -m http.server 4174 --directory design/app-prototype
```

Then open:

| Page | What it is |
| --- | --- |
| `http://localhost:4174/` | The app. Write, speak, swipe to the chats, open Settings. The side panel jumps to any flow. |
| `http://localhost:4174/?scene=tour` | A walkthrough that plays the whole flow by itself, pressing the real controls. |
| `http://localhost:4174/frames.html` | Every screen as a still frame, in light and dark. Click a frame to open it live. |

Any static server works. Opening `index.html` from the file system does not: the bear's pictures are cut
from `assets/bear-poses.png` on a canvas, which a browser refuses for `file://` pages.

### On an iPhone or the Simulator

On a phone-sized screen the prototype drops its drawn bezel and side panel and fills the screen. Open the
address in Safari, or, for the real thing, add it to the Home Screen (Share, Add to Home Screen, Open as Web
App): it then runs full screen under the real status bar, and its island sits on the phone's own. The
Simulator reaches the Mac's server at `http://localhost:4174/`.

The glass island bends what is behind it with a filter that only Chromium browsers support. Other browsers
show plain blurred glass.

## What it shows

- **Front page.** A new chat: Poki in a window of sky, two suggestions, one glass input.
- **Speaking.** The input's black button offers Dictate (your words become text) and Talk with Poki (a live
  conversation). A talk is kept as a card of what came of it, not as a transcript.
- **Phone tasks.** Poki works in the other app and is only in the Dynamic Island. Nothing is drawn in the chat
  until the task has ended; then the chat gets one card.
- **The record card.** The apps and the time, the steps Poki named, the step you did yourself or allowed, and
  every action on request.
- **Chats and Settings.** The window shrinks into the New chat button. Settings is one status card, four rows
  and the approvals switch; every setting the app has today sits behind one of them.

## What is real and what is not

The prototype only shows data the app has today, with these exceptions:

| In the prototype | In the app today |
| --- | --- |
| The island's button pauses Poki and resumes it | The button stops the runner; there is no pause. Proposed in [`../proposal-pause-and-talk-card.md`](../proposal-pause-and-talk-card.md) |
| A talk leaves a card of outcomes | The chat keeps the whole conversation. Proposed in the same document |
| The island can be switched to clear glass in the side panel | iOS paints a Live Activity's island solid black, which is the default here |

The app has one thing the prototype does not: the plus in the message field, which adds up to four pictures
to a message.

What the app does have, and the prototype relies on:

- Every action has a label in the app's own words (`Open Mail`, `Tap “Send”`), the app in front, and whether it
  went through (`AppModel.swift`, `ActionLog.swift`).
- Poki's own tasks have a plan of up to eight named steps (`report_plan`) and a final verdict (`finish_task`),
  both in `ChatModel.swift`. Outside agents have neither.
- There is a running count of actions, never a total. So nothing here says "step 2 of 5".

## Files

```
index.html            the page: side panel, the phone's mount point, the scripts in order
frames.html           the board of every frame
css/app.css           every style outside the island
assets/bear-poses.png the bear's poses, one sheet
js/
  util.js             two helpers
  hue.js              Poki's light: five hue sets in OKLCH
  bear-art.js         cuts the bear's sheet into poses and layers
  markup.js           the phone's HTML
  chats.js            sample chats and shared state
  puppet.js           the bear: states, moves, the clock that keeps it alive
  app.js              moving between screens, drawing chats, the question and task flows
  settings.js         every Settings page, as data
  first-run.js        the first-run screens
  records.js          the card a phone use leaves in a chat
  scenes.js           every frame as a state (?scene=… or ?frame=…)
  voice.js            the speak menu, dictation, a live talk
  events.js           clicks, keys, dragging between pages
  page.js             the page around the phone, URL options
  island-style.js     the island's style sheet
  island.js           the Dynamic Island, in its own shadow root
  walkthrough.js      the self-playing walkthrough
  boot.js             start
```

The scripts are plain `<script>` files that share one scope, loaded in the order `index.html` lists them. Each
builds on the ones before it.

URL options: `mode=light|dark`, `mix=1…5` (the hue set), `scene=<name>` (open a state, live), `frame=<name>&embed=1`
(the same state as a still picture), `isl=line|peek|quiet` and `mat=glass|black` (the island).

## How this becomes the app

The redesign ships by changing the SwiftUI views, screen by screen. There is no web view in Poki and this
prototype does not add one.

| Prototype | App code |
| --- | --- |
| Colours and type | `Poki/Front/Paper.swift` |
| Front page, Poki's window and its light | `Poki/Front/FrontPages.swift`, `SkyWindow.swift`, `PokiBear.swift`; `Shared/PokiLight.swift` |
| A chat, the message field, pictures | `Poki/Chat/ChatView.swift`, `ChatPictures.swift`, `ChatModel.swift`, `MessageBubble.swift` |
| Chats list | `ChatsPage` in `Poki/Front/FrontPages.swift`; `Poki/Sessions/SessionStore.swift` |
| The record card | `Poki/Front/UseCard.swift`; `ChatEntry.Kind.plan`, `PlanStep` in `ChatModel.swift`; `Sessions/ActionLog.swift` |
| The island | `Shared/ActivityViews.swift`, `ActivityFace.swift`, `ActivityTheme.swift`, `PokiActivityAttributes.swift`, `Poki/Activity/ActivityController.swift` |
| Speaking | `Poki/Voice/VoiceModel.swift`, `VoiceView.swift` |
| Settings | `Poki/Front/FrontSettings.swift`, `App/MainTabs.swift`, `Chat/ModelSettingsView.swift`, `Connect/SettingsView.swift`, `Connect/MemoryView.swift`, `Signing/SigningViews.swift`, `Debug/DiagnosticsView.swift` |
| First run | `Poki/Front/FirstRun.swift`, `Poki/Setup/SetupView.swift`, `App/SetupState.swift` |

Paths are under `native/ios-app`. Every string the app shows goes through its String Catalogs
(`Shared/Localizable.xcstrings`, `Shared/LiveActivity.xcstrings`); the prototype is English only.

If a web version is ever needed for real, follow Poki Setup (`desktop/app`): React, TypeScript and Vite, with
plain CSS.

## Not cleaned up yet

- The code grew by iteration and was split into files afterwards. `app.js` and `events.js` still mix several
  concerns.
- An earlier call screen is still in the code (`call`, `endCall`, `.callui`) though no flow reaches it.
- Rows that would open a picker or a form show "not part of the prototype".
- Motion was checked from still frames and state logs, not on a phone.
