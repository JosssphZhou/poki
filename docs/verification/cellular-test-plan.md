# Cross-network connection checks

## Remote session lifecycle

Capture a remote phone through MCP, close the client, restart the daemon, and capture the same phone from a new client.

1. Protect continued use when clients disconnect or the daemon restarts.
2. A replacement helper cannot connect once the fixture refuses new connections, so dropping the old process makes the next screenshot fail.
3. Existing USB and simulator tests do not cover RemotePairing session lifetime.
4. Use the existing MCP integration fixture without adding a production test hook.

## Physical iPhone checks

Initialize on Wi-Fi, disconnect USB, and switch to cellular. Verify screenshots, app launch, and exact text readback in a search field. Clear the test text without submitting it. Test explicit reconnection and complete connection loss separately. Use only the authorized iPhone.

## Tool catalog contract

The three existing protocol checks cover default and full HTTP discovery, per-client stdio profiles, and the independent Poki Agent client. Adding reconnect_device and disconnect_device raises the complete catalog count from 56 to 58. Keep the default task catalog limited.

Each entry point has distinct filtering or configuration propagation behavior. Reuse the existing real MCP discovery tests without adding test-only production entry points.
