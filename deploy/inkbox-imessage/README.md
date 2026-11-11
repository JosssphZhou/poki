# Poki via Inkbox iMessage

This Cloudflare Worker receives a signed Inkbox message, calls the phone's `ask_poki` through a dedicated Poki Relay connector, then replies by Inkbox conversation ID. Poki uses the model selected on the iPhone. This bridge handles text. The phone stays responsible for carrying out actions and must be reachable through its Relay.

## Local verification

From this directory with Node.js 22 or later:

```sh
npm ci
npm test
npm run build
```

The integration test uses the Poki Relay implementation from this repository, a simulated iPhone, and simulated Inkbox requests and replies. It checks relay OAuth, signed intake, sender and group filtering, duplicate delivery, an unfinished Poki task, and the two-turn exchange “打开设置” → “再点通用”. No real message is sent by the test.

## Connect to your phone

1. In Poki, open **Diagnostics → Testing** and turn on **ask_poki Tool**. Configure a supported model for text chat and ensure the phone is online in Poki Relay. If the tool does not appear, reopen Poki.
2. In Poki **Agents**, add a separate connector for Inkbox. Its full URL is a credential. Do not paste it in a public log or commit it.
3. Set `POKI_MCP_URL` privately. To check the phone before connecting Inkbox, run `npm run check:phone` with that variable in the local shell environment. The check only initializes a session and lists its tools.

## Configure the bridge

For local development, create a private `.dev.vars` in this directory and run `npm run dev`. To move it to Cloudflare, create a separate Worker using the provided Wrangler config. Set the same values as Worker secrets, then deploy this Worker. The existing Poki Relay is a separate service.

| Setting | Value |
| --- | --- |
| `POKI_MCP_URL` | Full URL of the dedicated Poki connector |
| `INKBOX_API_KEY` | API key scoped to this Inkbox identity |
| `INKBOX_SIGNING_KEY` | Webhook signing key for the same identity |
| `INKBOX_ALLOWED_SENDER` | Your own iMessage phone number in international format, e.g. `+15555550100` |
| `INKBOX_CONVERSATION_ID` | Optional. Pin the bridge to a particular Inkbox conversation ID |

Set up a webhook subscription for that Inkbox identity, with the bridge's HTTPS `/webhook` endpoint, the `imessage.received` event, and `context_config: {"texts":{"mode":"count","count":8}}`. The Worker also stores up to eight recent messages and receipts per conversation so a follow-up queued before the last receipt still has context. Keep the subscription limited to the Inkbox identity dedicated to your Poki. The bridge accepts only direct iMessage from the configured number.

On a shared Inkbox line, follow the console's connect instructions from your iPhone. In the assigned iMessage conversation, send “打开设置”, wait for the response, then send “再点通用”. Verify both actual screens and replies. For a travel test, disconnect Wi-Fi and repeat on cellular.

If the phone or Relay is unavailable, the bridge returns a failure receipt. It does not replay a possibly executed phone command. Inkbox reply retries use a stable idempotency key. Phone operations remain subject to Poki's own lock screen and approval behavior.

Protocol references: [Inkbox iMessage and webhooks](https://github.com/inkbox-ai/inkbox/blob/main/sdk/python/README.md#imessage), [Poki Relay client guide](../cf-relay/CLIENT.md).
