# Note for Joseph's agent: the MCP work on `dev/mcp-agent-tools`

Written Nov 7 2026, 1:30 am ET, for Joseph and the agent working for him. Zhehan is away and cannot
test further builds, so this round's work is on the branches as it stands. It was developed on
Zhehan's fork (ZhehanZhang/poki-remote) on top of a Linux host stack, then ported onto this repo's
`main` (7ee03e3) without the Linux-only parts. Nothing on `main` was changed and no PR is open.

The companion branch `dev/ios-standalone` carries the on-phone side: the Poki iPhone app, the
on-phone runner, and PokiCore, a Swift MCP with the same `look`/`do` tools served from the phone. Its
notes are `docs/NOTE-FOR-JOSEPHS-AGENT.md` and `native/ios/PokiCore/NOTE-FOR-UPSTREAM.md` on that branch.

## Ground rules

- Do not merge into `main` without Joseph's review (CODEOWNERS). Open a PR only when Joseph asks.
- No workflow on this branch runs on a push; it adds none.
- Every commit is a single concern with its own test; read them in order (`git log main..`).

## What is on this branch (17 commits, oldest first)

Reading the screen and reporting what an action did:

1. The post-action readback deadline follows the measured cost of one accessibility read on a
   physical device (3 reads plus settle, 5 s floor, 12 s cap). Over a slow tunnel one read takes
   1.5 to 2.7 s, and the fixed 5 s dropped the whole observation.
2. When that deadline fires, the last complete read is reported (`screen.partial`) instead of
   `unavailable`.
3. `screen_change` is `changed`, `unchanged` or `unknown`. `unknown` is never a failure, and the
   no-change advice attaches only to a verified `unchanged`. `screen_changed` and
   `screen_change_verified` stay for existing clients.
4. Batches: a coordinate tap is compared with the screen before it only when that can hold back a
   later step, so a run of coordinate taps goes without per-step reads (six taps: 61 s down to 10 s
   over the tunnel). A step that says `verify: true` is always compared (the last commit; it restores
   the `no_change` stop your `verify:false` test expects).
5. Approval-gated results say who approved them, and `poki_mcp_status` lists `approval_covers`.
6. `launch_app` on a phone ends with the screen and says `resumed` when the app was already running;
   `fresh: true` terminates it first; the foreground is polled for at least 2 s.
7. A touch is not called unchanged while the next screen is still arriving: the comparison includes
   the app in front, and an unchanged read is confirmed once more (up to 2.5 s after an app-icon tap).
8. Every screen carries `observed_at` and `tree_age_ms`; a read that began before the last input is
   never reported as the current screen.
9. `take_screenshot` says the capture does not go into Photos (an agent reported a false bug).
10. `poki_mcp_status` shows a build commit recorded without git; SpringBoard is named
    `com.apple.springboard` when AppService knows it only by its executable.
11. `scroll` and `scroll_to` take `container` (the label of the list or row) and `pages`; sideways
    lists move a page at a time without coasting, and the answer names what moved.

Serving several clients:

12. `POKI_INPUT_LOCK=1`: each MCP session gets its own queue, reads run beside other sessions' work,
    and input takes a per-device lock. Off by default; the single queue is unchanged without it.
13. `POKI_MCP_CALL_LOG=<path>`: one JSON line per tool call (tool, duration, verdict, failed). Never
    arguments, text or images.

Bridge (`native/bridge`), three new ops, documented in `native/NATIVE.md`:

14. `type_keys` (hardware key presses on one keyboard session, no pasteboard), `pasteboard`
    (get, items, set), `app_for_pid` (names the app behind a pid-only accessibility root).

The look/do profile:

15. `POKI_TOOL_PROFILE=cua` lists `look`, `do` and the device and status tools. `do` runs actions in
    order and reads the screen once; the answer is numbered elements, what is new and gone, and a
    screenshot, with no verdict. Typing uses `type_keys` and pastes only what the keyboard cannot
    type, with the user's clipboard saved and put back. `POKI_CUA_BACKEND=wda` with `POKI_WDA_URL`
    drives a WebDriverAgent runner on the phone instead of the bridge (`src/cua-wda.mjs`). The
    complete catalog (`POKI_MCP_TOOLS=all`) now has 60 tools, so Poki Agent sees `look` and `do` too.
    Docs: "Computer-use profile" and "One daemon, several clients" in `docs/tools.md`.

## Tests

Run on Linux against this branch and against `main` for comparison (`node --test test/*.test.mjs`,
`cargo test` in `native/bridge`):

- New tests pass: `test/cua.test.mjs` (8), `test/cua-wda.test.mjs` (4), `test/input-lock.test.mjs`
  (11), `test/scroll-container.test.mjs` (2), `test/observation.test.mjs` (14); bridge 16/16.
- The failures that remain are the same on `main` on Linux, because they need macOS tools (`plutil`,
  `xcodebuild`, the update check). Please run the full suite on a Mac before merging anything.
- Nothing here was run on a phone from this repo's code. The behaviour was measured on Zhehan's
  iPhone 17 Pro (iOS 27.3 beta) with the fork's version, which has the same logic on a Linux host.

## Left in the fork on purpose

The `observe`/`act`/`run` agent profile with a screen-as-state model, live video frames from a
long-lived bridge daemon, Linux OCR and developer-disk-image install, and an OAuth front for a remote
daemon. They depend on a Linux host daemon this repo does not have, and the look/do profile replaced
the agent profile as the direction.

## How the two MCPs could unify

The phone-side MCP (PokiCore, Swift, on `dev/ios-standalone`) and this Node MCP can expose one
contract, so an agent written for one works on the other:

- **Two tools, `look` and `do`, facts only.** No verdicts and no task-specific heuristics; the model
  decides what happened from the elements and the picture.
- **PokiCore's answer shape is the more mature one** and is pinned by its tests
  (`native/ios/PokiCore/Tests`, strings in `docs/ios-core.md`). It differs from `src/cua.mjs` here
  in ways worth adopting: element numbers that persist across reads (here they are replaced by each
  read), a `screen_changed` line, per-action `sent | not_sent | unknown` with a time, a note line for
  anything odd (full-screen container tapped, numbering restarted on a new screen), the picture at
  one pixel per point, the XML `/source` tree from WDA (3 to 7 times faster than JSON), and WDA
  session rules (a timed-out read keeps the session; a timed-out action ends it so nothing queued
  runs late).
- **Porting those into `src/cua.mjs` and `src/cua-wda.mjs` is about a day**, and a Node test can
  replay PokiCore's fixtures.
- **Two transports under one contract:** the bridge (Mac or another host with the developer
  connection: installs, logs, raw HID, a fresh runner) and the runner on the phone (no computer after
  pairing; avoids the RemoteXPC services behind issues #1 and #6, but needs the signed runner and the
  personalized developer disk image, #18). Chosen per device behind the same tool names.
- **Phone-only pieces stay in the app:** Live Activity approvals, the runner's wake and loopback, the
  relay, the rule that Poki in front after a tap is undone.
- **Worth one shared module:** element numbering and matching across reads, the picture-change grid,
  the sensitivity words (payment, deletion, sending; 12 languages), paste with clipboard restore, and
  the deadline rules.

Open questions for Joseph: XML or JSON tree; whether the relay should be one entry point for both
MCPs (an agent on a Mac could use it too); how a `back` action should work on iOS (navigation-bar
button, edge swipe, per-app answer); and whether `look`/`do` should join the default tool list or
stay a profile.
