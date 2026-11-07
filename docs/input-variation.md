# Optional input variation

Draft extraction from #31. Coordinate the public switch with #11 before merge; this draft is not a proposal to ship two variation switches.

Add `"variation": true` to `tap`, `tap_text`, `long_press`, `double_tap`, `swipe`, `drag`, `scroll`, or `scroll_to`.

- Adds 40–120 ms before input and varies default gesture duration by up to 15%.
- Single taps on an observed element/ref may shift at most 3 points per axis, confined to its middle half. Coordinate-only taps retain their exact location.
- Explicit durations, swipe endpoints, text input, alert handling, and unlock digits remain unchanged. Double taps and long presses vary timing only.
- Cancellation during the delay sends nothing. Existing device serialization still applies.

This is bounded input variability, not a guarantee of human equivalence or avoidance of app detection. It adds a small delay and does not address connection or screenshot latency.
