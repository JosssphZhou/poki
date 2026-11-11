# Foldable display experiments (unfinished)

This is the local experimental snapshot requested in issue #20, based on commit
`7ee03e3`. It is shared for maintainer review, not as verified two-display support.
The installed MCP checkout was rolled back separately and remains unchanged by
this draft. The runtime changes in this draft are the archived experiment; only
these handoff notes were updated for publication.

## Observations and hypotheses

On a two-integrated-display physical iPhone, the cached AX subscription returned
one SleepLockScreen root with no children while the unlocked Settings app was
visible. Control Center could produce a populated SpringBoard tree. The reason
for the cached service's selection is not established.

With the inner panel active in portrait, the primary panel was inactive. The
DVT default screenshot could be black, whereas a CoreDevice screenshot explicitly
selecting the active panel produced a normal image. HID enumeration exposed a
separate touchscreen service for each panel.

## Experimental changes

- Discover the active integrated display through CoreDevice device information.
- Select its unique ID for secondary-panel screenshots and its numeric ID for
  input media. Select the corresponding touchscreen HID service by unique ID.
- Keep the existing drag and multitouch scheduling, release/error handling, and
  text-field confirmation, focus, clipboard, read-back, and submission guards.
- On devices with multiple integrated panels, prototype live AX hit tests,
  application-reference requests, and attribute traversal using the existing
  keyed-archive parser and field/role mapping.
- Require matching application PIDs at three sampled positions before and after
  traversal. Reject ambiguous applications, failed attribute reads, display
  changes, deadline expiry, and walks exceeding 256 visited elements.

## Validation status

- Earlier local observations: an explicitly selected inner-panel screenshot and
  a live Settings traversal agreed on a 669-by-951-point portrait viewport. The
  traversal returned 27 elements including a SearchField, with stable field
  object identities across reads.
- The earlier media-only adjustment left a search-field tap with no observed
  change, and its batch stopped before text input.
- The final unique-ID-to-HID-surface candidate built but was not accepted on
  hardware. The phone had changed to a landscape lock screen before that final
  attempt, so its precondition check stopped before any tap or text was sent.
- Native regression tests for the archived snapshot: 21 passed.
- JavaScript regression results and exact commands are recorded in the draft PR.
- Text entry, text read-back, clearing the test query, and USB-disconnected Wi-Fi
  operation have not passed hardware acceptance.

## Review limits

These limits describe the snapshot as it was handed over. The sections below
record what later commits changed: touch rotation, phones with one built-in
panel, and the hardware checks. Panel changes during an existing media session,
external displays, split applications, system paste prompts and older developer
images still need review and hardware checks. Three hit-test samples are not an exhaustive visible
application inventory, and live AX decoding remains an experimental protocol path.
The 256-element limit refuses larger trees rather than returning partial results.

The snapshot itself was not rebased and got no further runtime fixes or phone
experiments while the handoff was prepared; the rebases and fixes that followed
are described below. Only synthetic display identifiers and synthetic AX reference fixtures are
included. Raw logs, captures, pairing records, runtime settings, device UDIDs,
account labels, network names, credentials, and local filesystem paths are omitted.

## Rebase onto main and hardware acceptance

The three commits above are unchanged apart from conflict resolution. Three
later commits rebase them onto `8b780c2` and fix what that exposed:

- `display::active()` returns no display when the phone does not advertise
  CoreDevice device information. Callers then keep the single-display defaults:
  display 1, the main touchscreen HID service, the DVT screenshot and the
  cached AX subscription. The section on phones with one built-in panel below
  widens this to every phone without a second panel.
- Touch coordinates are rotated into the active panel's native axes, using the
  panel's `currentOrientation`.
- The AX read before text input gets 10 s instead of 4 s. This now applies only
  to a phone with a second built-in panel.

Hardware: iPhone19,4 running iOS 27.1, connected over RemotePairing on Wi-Fi,
with the inner panel unfolded in landscape (951 by 669 points, `rot90`).

- Taps landed on the intended controls in a third-party app's sidebar and
  switched its views. Before the rotation fix, a tap aimed at the Settings
  search field landed on a different control.
- In Settings, `type_text` into the search field confirmed the text by reading
  the field back, and the clipboard was restored. `tap_text` on the field's
  close button cleared it.
- An accessibility read of the Settings tree took 4.4 to 4.9 s warm and 22.6 s
  on the first read after the tunnel came up.

Still open:

- The first read after the tunnel comes up can take longer than the 10 s
  budget, so the first text input in a session can still fail before sending
  anything. A retry succeeds.
- `launch_app` on the inner panel reported that it could not confirm the
  launch, although the app opened.
- Rotations of 180 and 270 degrees and folding or unfolding during a session
  have not been tried on hardware.

## Second rebase onto main

`main` moved on to `ce504ac` and the branch was rebased again. The conflicts
were all in `native/bridge/src/ax.rs`:

- `Tree::update_for` keeps main's handling of streamed dumps and this branch's
  decoding of single live responses. An initial or destroyed dump still discards
  the cached graph. It now keeps the display orientation as well as
  `include_offscreen`.
- The reply to the phone's `hostAPIVersion` call still carries 7, as on main.
  At that point the branch still sent it as a DTX object reply (payload type 3)
  and accepted `hostApiVersion` as a second spelling. Both were removed later;
  see the last section.
- Main's `stream_tests` and this branch's live-query tests are both kept.

`main` now compiles `ax.rs` into the launcher too, so the launcher also compiles
`display.rs`. At that point its accessibility reads asked for the active display
in the same way as the bridge while its touch path still used the main
touchscreen. The last section removes that mismatch. `ax::Direct` does not ask
for the active display.

The hardware acceptance above was done before this rebase and has not been
repeated. The launcher change has only been compiled and unit-tested on a Mac.

## Phones with one built-in panel keep main's path

Review of the rebased branch found that a phone with one built-in panel no
longer behaved as on `main`: every request opened a device-information
connection, a failed display query stopped input, and the touch surface,
rotation, screenshot path and pre-input wait all depended on the answer.

`display::active()` now returns a display only for a phone that reported more
than one built-in panel. For every other phone it returns none, and
`display::route(None)` gives main's values in one place: display 1 for input
media, the main touchscreen (257), no rotation, the DVT screenshot, the cached
AX subscription and a 4 s read before text input.

- A phone that reports one built-in panel is remembered for the life of the
  process and not asked again. The cost is one query per helper process, not
  one per request.
- A query that fails, times out after 2 s or does not parse leaves such a phone
  on main's path. After three such failures in a row the phone is no longer
  asked.
- Only a phone that has already reported several panels gets an error from a
  failed query, because main's path would read and touch the wrong panel there.
- The query inside an AX read is bounded by that read's deadline.
- The single-display fallback to a touchscreen named `CoreDevice
  touchscreen(nil)` is gone. A phone with one panel never reaches the lookup by
  name.
- On USB, the JavaScript side asks the helper once per phone whether it has a
  second panel (`panels`). Only then does the screenshot go through the helper.
  Otherwise it runs the same `poki-native screenshot` command as `main`.

The reply to `hostAPIVersion` is main's again: payload type 0, and only that
spelling is answered. Nothing observed on hardware required the other form.

The launcher keeps main's path on every phone. It compiles the shared files with
`ROUTES_BY_PANEL` off, so its AX reads use the cached subscription and its taps
go to the main touchscreen, as before this branch. It does not follow the
active panel of a two-panel phone.

The limit of 256 elements in a live read is unchanged. A longer screen on a
second panel still fails with `AX tree exceeded 256 elements`.
