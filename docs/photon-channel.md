# Optional iMessage channel through Photon

Poki can receive iMessage tasks through [Photon](https://photon.codes/docs/beta/photon) instead of BlueBubbles. Photon hosts the iMessage line, so this channel needs no Messages sign-in, no BlueBubbles Server and no macOS permissions for them. Poki Agent itself still runs on your Mac: Photon replaces only the way messages reach it. Install it only if you want it. The normal `./bin/setup` build, the [BlueBubbles channel](imessage-gateway.md) and Telegram do not use Photon.

This channel uses Photon Beta (2.0): the API at `https://api.photon.codes`, the `@photon-ai/api` client and the Socket.IO event stream. Photon describes Beta as a preview and its contract can change. The worker pins the event contract dated `2026-07-01`.

## Before you choose it

| | BlueBubbles | Photon |
| --- | --- | --- |
| Where messages travel | Between Messages and Poki on your Mac | Through Photon's servers |
| What you run | A Mac signed in to Messages, with BlueBubbles Server | Only the Poki worker |
| The number you text | Your own Apple Account | A shared line Photon assigns to your sender |
| Credentials | A local server password | A Photon project API key |

Task text and replies pass through Photon. A reply can describe what is on the phone's screen. Use BlueBubbles if that text must stay on your own machine.

Photon filters one-time passcodes on iMessage lines, so do not rely on this channel to pass a verification code to Poki. See Photon's [iMessage notes](https://photon.codes/docs/beta/messaging/imessage).

## Requirements

- Python 3.11 or newer for the setup command, which needs nothing else on the computer.
- For the worker: a working [Poki Agent](../agent/README.md) on the same computer. That means the `./bin/setup` build, which needs macOS with the full Xcode, a paired iPhone, Node.js 24 or later, `npm ci --prefix agent` and model login. Setup says so at the start when the build is missing, and the launcher names what is missing when you start it.
- A Photon account. Setup signs you in, prepares the Photon Beta project and creates its API key, so you need no project or key beforehand.
- A plan with shared iMessage capacity. See Photon's [plans](https://photon.codes/docs/beta/plans-and-billing).
- One iMessage identity you send from: a phone number with country code, such as `+14155550123`, or an Apple Account email. On iPhone, **Settings → Apps → Messages → Send & Receive** shows it. A number and an email are different senders.

## Configure

From the repository root, run:

```sh
./bin/setup-channels --channel imessage
```

Setup describes the two ways Poki can reach iMessage, BlueBubbles and Photon, and asks which one to use. Choose Photon, or skip the question with `--provider photon`. It then asks for the allowed sender and the Poki device name or ID, and signs you in to Photon:

1. It prints a link and a code, and opens the link in your browser. Check that the page shows the same code and approve. This is Photon's device login, the one `photon login` uses, so setup never sees your password. The code is valid for a few minutes. You can also open the link on another device. Setup opens a browser only in a terminal on a computer with a desktop, never when `CI` is set, and not with `--no-browser`.
2. It uses your Photon project named `Poki Agent`, and creates that project when your account has none of that name. Running setup again therefore reuses the same project instead of adding another. To use a project you already have, pass its name, for example `--project-name "My project"`; a name that matches no project creates one with that name. An account that belongs to several organizations is asked which one gets a new project.
3. It creates a project API key named `Poki Agent on <this computer's name>` in that project and stores it. The key has `project:read` and `project:write` for the worker, and `platforms:read` and `platforms:write` to map your sender to a line. It does not expire. Revoke it under the project's API keys in the Photon dashboard when you stop using this channel.
4. It maps your sender to a shared iMessage line in that project and prints the number to text. This uses one shared iMessage assignment from the project's plan. If the sender already has a line in that project, setup prints that line's number. If Photon refuses the assignment, setup says why, keeps the configuration and leaves the step to you, as described under [Assign a shared line](#assign-a-shared-line).

The sign-in is used for these steps only and is not stored. The worker runs on the project key.

Setup creates `~/.config/poki-agent/photon/`:

- `photon.json`: sender, device and ChatGPT authentication selection.
- `connection.json`: project ID and API key. Keep this file private.
- `state/`: created by the channel later for its cursor and task records.

The directory has mode `700` and both JSON files have mode `600`. Setup prints no key, sends no message and starts no worker. An existing destination causes an error before any sign-in and is left unchanged. If the sign-in is denied or its code expires, no project or key is created and nothing is written. A project that setup created stays in your account when a later step fails, and the next run finds it by name. If setup fails after it has created the key, it revokes that key and says so. When it cannot revoke it, it names the key so that you can revoke it in the Photon dashboard. Use `--config-dir /path/to/clean/photon` for another destination, and pass the same option to the launcher below.

For setup without questions, use `--provider photon --answers /path/to/private-answers.json` with mode `600`:

- With `sender` and `device` only, setup still signs in. It prints the link without opening it and waits, so an agent that runs setup for you can pass the link on. Add `projectId` to use one project by its ID, or `organizationId` when the account belongs to several organizations: setup then looks for the project in that organization only and creates it there.
- With `sender`, `device`, `projectId` and `apiKey`, setup contacts no service and stores the key you supply. That key needs `project:read` and `project:write`, plus `platforms:read` and `platforms:write` if Poki should assign the shared line.

Keep the answers file outside the repository and remove it afterwards. Do not put a key in command arguments, shell history, screenshots or logs.

## Assign a shared line

A shared line serves one sender. Setup maps your sender to a line and prints its number. Run this yourself when setup could not, when you supplied your own key, or to see the number again:

```sh
node bin/poki-photon.mjs --assign
```

This prints the assigned number. It uses one shared iMessage assignment from the project's plan. If the sender already has a line, the command prints that line's number instead of creating another. If the key lacks `platforms:write`, assign the sender in the Photon dashboard under **iMessage** instead, as described in Photon's [iMessage guide](https://photon.codes/docs/beta/get-started/imessage).

Then, from the allowed sender, start a new direct iMessage conversation with the assigned number and send a message. A shared line cannot message first: Photon refuses replies until the sender has texted the line since the assignment.

## Check, then start

```sh
node bin/poki-photon.mjs --check
```

This loads the key privately, authenticates and subscribes to the project's event stream. It sends no message, saves no cursor and starts no phone task. A successful check confirms the project ID, the key and its `project:read` permission. It does not confirm `project:write`, the assignment or message delivery.

Once Poki's MCP service, the selected device and model access are ready, start the channel explicitly:

```sh
node bin/poki-photon.mjs
```

Keep this process running. Do not run two workers for the same configuration directory, and stop the worker with Ctrl-C before moving or removing its private configuration.

To supply credentials through the environment instead, export `PHOTON_PROJECT_ID` and `PHOTON_API_KEY` and run `poki photon --config <private JSON file>`, as described in the [agent guide](../agent/README.md#configure-imessage-through-photon).

## What the worker does

Only plain-text messages from the configured sender in a direct conversation become tasks. Messages from other senders, group conversations, read receipts and typing updates are ignored without a reply. An attachment or voice message from the sender gets `Unsupported message. Send a plain-text task.`

The worker marks each message it takes from the configured sender as read. While a task runs it shows a typing indicator, from the first reply until the final one. Both are best effort: if Photon rejects one, the worker logs that once and continues without it, and replies are not affected. Whether "Read" appears on the sender's phone also depends on Photon and on iMessage settings.

Confirmations, `/stop`, task corrections and final results work as they do for the [BlueBubbles channel](../agent/README.md#configure-imessage-through-bluebubbles): one local confirmation, no progress messages, then the result. There is no reply ledger, because the agent has its own number and its replies do not return as incoming messages.

Only messages sent after the first start become tasks. The worker saves Photon's event cursor before it dispatches a task, so an interrupted task is not replayed after a restart, and messages sent while the worker was stopped are delivered when it starts again. Photon replays only events it still retains. Until the first event arrives after a fresh setup there is no cursor to resume from, so a message sent while the worker is disconnected in that window is not recovered.

Each reply carries an idempotency key. The Photon client makes up to three attempts on a transient failure, all with the same key, so a retry cannot post the reply twice. Photon accepts replies for asynchronous delivery; acceptance is not delivery. If Photon later reports that a reply failed, the worker logs it. A rejected or uncertain reply stops the worker without another resend. Check the conversation before restarting.

A dropped connection reconnects on its own and resumes after the last event received; the worker logs the disconnect and the resume. If Photon closes the event stream explicitly or refuses the key, the worker stops and names the cause.

## Verification scope

The channel is covered by synthetic tests run on Linux with Node.js 24: `agent/test/fixtures/photon.mjs` serves a local Photon REST and Socket.IO API, and the tests drive the real adapter, launcher, setup command and message worker against it. They cover sender scoping, skipped history, cursor resume after a restart and a dropped connection, replayed events, the reply payload, idempotent retry, rejected replies, read receipts, typing indicators, the choice between BlueBubbles and Photon, the device sign-in, finding or creating the project, key creation, the line assignment during setup and private configuration. They send no real messages.

The browser sign-in, project creation and line assignment against the live Photon service, receipt and delivery through it, Photon's retention and rate limits, and a task on a physical iPhone need a separate authorized run. The synthetic results do not prove them.
