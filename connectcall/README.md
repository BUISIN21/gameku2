# ConnectCall

Video and audio meetings that work in an **Android app** and in a **laptop browser**,
built with Flutter, LiveKit and a small Node.js/TypeScript API. The name is a
placeholder: change it with `--dart-define=APP_NAME=...`.

**Status: Phase 2 (basic working call).** Create a meeting, share the code, and join
from Android or a browser. Real-time video and audio with mute, camera on/off,
front/rear camera switch, device picker, connection status, call duration,
reconnection and permission handling. Accounts, invitations, chat and
notifications come in Phases 3–5 (see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)).

| Folder | What |
|---|---|
| `app/` | Flutter app (Android + web) |
| `backend/` | API that creates rooms and issues short-lived LiveKit tokens |
| `e2e/` | Automated real two-browser call test |
| `docs/` | [Architecture & costs](docs/ARCHITECTURE.md) · [Setup](docs/SETUP.md) · [Testing](docs/TESTING.md) · [Deployment](docs/DEPLOYMENT.md) |

Quick start: [docs/SETUP.md](docs/SETUP.md).

**Security note:** traffic is encrypted in transit (HTTPS, WSS, DTLS-SRTP).
ConnectCall is **not** end-to-end encrypted. See ARCHITECTURE.md §6.
