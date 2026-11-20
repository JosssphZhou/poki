# Third-party notices

Poki Agent includes task execution, route learning, fast execution and prompts copied from Poki App. The source revisions and adaptations are listed in [SOURCES.md](SOURCES.md). Poki code in this repository uses the AGPL-3.0-only license in the repository root.


The pi coding-agent and pi-ai packages are installed as dependencies, version 1.5.0. Their package license files apply. This repository does not copy their credential stores or login implementation.

The Photon channel installs [`@photon-ai/api`](https://www.npmjs.com/package/@photon-ai/api) 0.7.0 (Apache-2.0) and [`socket.io-client`](https://github.com/socketio/socket.io) 4.8.3 (MIT) as dependencies. The channel tests install [`socket.io`](https://github.com/socketio/socket.io) 4.8.3 (MIT) as a development dependency. Their package license files apply, and `package-lock.json` names their transitive packages.

The Telegram adapter ports selected message reception, authorization, splitting, retry and progress-editing logic from Nous Research's Hermes Agent, copyright 2025 Nous Research, under the MIT license. The supplied license is in [licenses/hermes-MIT.txt](licenses/hermes-MIT.txt). Source functions and adaptations are listed in [SOURCES.md](SOURCES.md).
