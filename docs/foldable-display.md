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

The display's reported bounds are used directly. Rotation, panel changes during
an existing media session, external displays, split applications, system paste
prompts, older developer images, and single-display compatibility still need
review and hardware checks. Three hit-test samples are not an exhaustive visible
application inventory, and live AX decoding remains an experimental protocol path.
The 256-element limit refuses larger trees rather than returning partial results.

This snapshot has not been rebased onto subsequent upstream changes. No further
runtime fixes or new phone experiments were made while preparing this handoff.
Only synthetic display identifiers and synthetic AX reference fixtures are
included. Raw logs, captures, pairing records, runtime settings, device UDIDs,
account labels, network names, credentials, and local filesystem paths are omitted.

## Rebase onto main and hardware acceptance

The three commits above are unchanged apart from conflict resolution. Three
later commits rebase them onto `8b780c2` and fix what that exposed:

- `display::active()` returns no display when the phone does not advertise
  CoreDevice device information. Callers then keep the single-display defaults:
  display 1, the main touchscreen HID service, the DVT screenshot and the
  cached AX subscription.
- Touch coordinates are rotated into the active panel's native axes, using the
  panel's `currentOrientation`.
- The AX read before text input gets 10 s instead of 4 s.

Hardware: iPhone19,4 running iOS 27.1, connected over RemotePairing on Wi-Fi,
with the inner panel unfolded in landscape (951 by 669 points, `rot90`).

- Taps landed on the intended controls in a third-party app's sidebar and
  switched its views. Before the rotation fix, the same taps landed elsewhere.
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
