# Cellular native-listener diagnosis (2026-11-06)

Status: unresolved. This investigation does not establish a repair or full product acceptance.

Scope: the same paired iPhone17,1 on iOS 27.3, Tailscale connected, USB disconnected.

## Direct observations

1. Enabling the phone's own Personal Hotspot while on cellular did not restore either RemotePairing (49152) or lockdown (62078). Both IPv4 and IPv6 refused connections. The user subsequently disabled the hotspot.
2. After returning to Wi-Fi, an authenticated native tunnel exposed `com.apple.mobile.wireless_lockdown/EnableWifiConnections = true`. Missing wireless permission therefore does not explain this reproduction.
3. Native process logs were attached over that tunnel before the next Wi-Fi-to-cellular transition. At approximately 27.5 seconds after capture began, `remotepairingdeviced` removed flow registrations for listeners L12 and L13. It then cancelled their retired inboxes on `utun8`. The listener path reports changed from `en0`, using Wi-Fi, to `pdp_ip0`, using cellular. `lockdownd` subsequently reported `wifi_link_down_callback`.
4. The logs also contain interface-type prohibition messages. Their private fields are redacted by iOS. They do not reveal the exact policy flag or map listener handles to specific port numbers. The evidence supports a device-side listener/interface restriction; it does not identify a public setting that changes it.
5. With the phone still on cellular, a bounded TCP probe of ports 49152–65535 at the configured Tailscale IPv4 address completed in 30.64 seconds. Of 16,384 ports, 16,382 refused connections; two accepted TCP. Neither completed authenticated RemotePairing within a four-second attempt. Their service identity remains unknown. This is not a scan of all ports or proof that every alternate protocol is impossible.

The existing product helper was left running. This round did not repeat screen/input acceptance, change production code, or rerun unchanged code tests. Prior successful warm-session checks remain separate from cold-reconnection acceptance.

## Protocol and upstream checks

The installed pymobiledevice3 11.34.1 implementation requests a TCP listener with a key, peer process information, and transport type. It exposes no cellular-interface override in that request. Its lockdown RemotePairing service documents that listener creation is unavailable on that control transport. These facts are about the inspected implementation, not an exhaustive specification of Apple's private protocol.

- [RoamRun's own requirements and cellular behavior](https://github.com/mh-mobile/RoamRun#working-away-from-the-mac) distinguish retaining an existing session from starting a new session, and require Wi-Fi for the latter. They also report that the phone's own hotspot does not satisfy that condition.
- [omarchy-apple-dev's real-device results](https://github.com/joshuaswarren/omarchy-apple-dev/blob/main/docs/OVER-TAILNET.md) independently report refusal of the RemotePairing entry point on cellular while Tailscale ping works.
- [pymobiledevice3 tunnel implementation](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/remote/tunnel_service.py) is the protocol reference inspected for listener creation and the lockdown service limitation.

## Consequence

Preserving an established session addresses client and Poki daemon restarts. It cannot be represented as recovery after the phone's outer tunnel is completely lost. No verified native mechanism was found in this investigation to reopen the cellular entry point. Adding retries or speculative request fields would not constitute a demonstrated fix.

Full cellular reconnection remains blocked for the tested native transport. This conclusion is limited to the measured device and examined protocols; it is not a claim about all iOS releases or every possible native mechanism.
