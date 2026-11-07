# LAN Bonjour recovery verification

Issue: [#30](https://github.com/JosssphZhou/poki/issues/30).
Final base: `9ce5e5e`, including the dead-tunnel RSD probe from `f55f98e` (#19).
The physical comparison used `2801d2b`; the later upstream changes add tests and
documentation, without changing the production RemotePairing implementation.

## Automated checks

- `npm test`: 145 passed on the `2801d2b` base. Subsequent upstream changes
  through `9ce5e5e` affect only native tests and documentation, not those Node
  production paths. The expanded scoped-IPv6 setup regression also passed separately.
- Final `cargo test --locked --manifest-path native/bridge/Cargo.toml`: 21 passed
  on the `9ce5e5e` base; native debug build, rustfmt check and diff check passed.

- `test/prepare-remote.test.mjs` executes setup with synthetic USB/pairing tools.
  It verifies persistence of `.local` names (rather than a one-time IP), existing
  IPv4/IPv6 setup (including interface-scoped IPv6), and rejection of
  malformed/non-local names before device access.
- `dead_bonjour_tunnel_drops_stale_control` failed on the latest
  base before the control reset, then passed after it. It uses real loopback
  sockets and a stopped tunnel adapter, not a real phone or authentication record.
  The follow-up uses an unadvertised `.local` name and asserts that the old control
  receives no bytes. It proves invalidation, not successful mDNS or authentication.
- `non_bonjour_recovery_keeps_using_its_existing_control` failed before restricting
  the reset to hostname mode, then passed after it. Numeric-IP/Tailscale recovery
  keeps the base implementation's control reuse.
- `failed_remote_replacement_keeps_the_working_tunnel` verifies that an explicit
  replacement failure does not discard an existing live tunnel. This also passes
  on the base: it protects the existing contract, not a newly fixed behavior.
- Existing upstream tests cover a silent phone, a stopped adapter and a refused
  service. The patch does not change the upstream retry gate: only reads and
  inputs known not to have been sent may retry; uncertain inputs are not replayed.

## Physical LAN address-change comparison, 2026-11-07

Two separately compiled debug helpers were kept running on one Mac against the
same paired iPhone 15 Pro over RemotePairing. One used the unmodified base, the
other the patch. Both read the same private configuration containing the actual
Bonjour hostname and the existing pairing-file reference. The baseline uses a
manually configured hostname because its setup command rejects hostnames.

Both helpers successfully read `device_info` before the change. The user switched
the phone between the same router's 2.4 GHz and 5 GHz Wi-Fi networks, which yielded
different IPv4 and IPv6 addresses. The user subsequently clarified that they did
not change the private Wi-Fi address setting. This is a Wi-Fi-network-switch
recovery test, not a same-SSID DHCP lease-renewal test. Frequency bands do not by
themselves imply separate IP subnets; subnet separation was not established.
No configuration edit, explicit reconnect call, helper restart, or re-pairing
took place between baseline and first post-change reads.

| Helper | First post-change read | Subsequent read |
| --- | --- | --- |
| Unmodified base | Failed after 36.106 s: old RemotePairing control connection closed | Succeeded after 1.028 s |
| Patch | Succeeded after 18.999 s within that request | Not required for recovery |

Each helper retained its original PID and configuration checksum. Host socket
inspection confirmed the patched helper's TCP peer changed to the newly advertised
address. Raw network addresses, device identifiers, pairing records and checksums
are deliberately omitted here. No screenshots, messages, audio or video were
captured or sent by this comparison.

The comparison ran before the final numeric-host compatibility guard was added;
that guard leaves the tested hostname recovery path unchanged. Its numeric-host
branch is covered by the separate regression above. The removed experimental
DNS-change detector was not present in either comparison helper.

A later test used the final patch `f6e5acb` through a dedicated MCP daemon.
The pre-change device-info request completed in 1.197 s. After another switch
between the router's Wi-Fi networks, the first request recovered in 20.672 s.
The native helper PID and configuration checksum were unchanged. This separately
exercises the final hostname path, including the compatibility guard; it is not
a claim that an end-to-end model-driven app task completed successfully.

## Limits

This is one controlled address-change comparison, not a latency or long-duration
reliability claim. Same-SSID DHCP lease changes have not been separately tested.
Recovery still waits for the existing transport/RSD timeouts;
it is not instantaneous. Renamed Bonjour hosts, changed advertised ports,
multiple phones, cross-network Bonjour, and IPv6 scope migration have not been
independently exercised. Numeric-IP/Tailscale compatibility is regression-tested,
not revalidated over a cellular network. Simulator operation was not tested on
hardware. Device pairing and UniqueDeviceID checks remain unchanged.

## Review follow-up

Explicit Bonjour reconnect now invalidates cached control before replacement,
while retaining the existing tunnel until a new one connects. A real-socket
regression asserts no bytes reach stale control and the old adapter remains live
on replacement failure. Non-Bonjour hostname configurations retain control reuse.
The physical runs above predate this follow-up; explicit reconnect after a real
address change has not been hardware-validated on this follow-up.

A real-loopback data-socket test checks that the authenticated control peer address
is reused with the new listener port. IPv6 scope migration remains untested.

Follow-up validation (2026-11-07): full Node suite 145 passed; updated setup
regression passed separately; full Rust suite 24 passed. The two new behavior
regressions were observed failing before their production fixes; the scoped-IPv6
zone classification regression also failed before its guard. The data-socket
loopback check covers its extracted connector, not full RemotePairing authentication.
