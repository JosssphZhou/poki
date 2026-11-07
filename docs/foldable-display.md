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
