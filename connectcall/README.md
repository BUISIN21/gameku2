# ConnectCall

Video and audio meetings that work in an **Android app** and in a **laptop browser**,
built with Flutter, LiveKit and a small Node.js/TypeScript API. The name is a
placeholder: change it with `--dart-define=APP_NAME=...`.

**Status: Phase 3 (accounts, private rooms, invitations).** Register and sign in,
create private rooms, invite people with expiring, revocable links, use an optional waiting room,
and hold video calls between Android and browsers. The owner can remove people or end the call
for everyone. Chat, contacts and notifications come in Phases 4–5
(see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)).

| Folder | What |
|---|---|
| `app/` | Flutter app (Android + web) |
| `backend/` | API: Firebase-authenticated rooms, invitations, membership, short-lived LiveKit tokens |
| `firebase/` | Firestore security rules and indexes |
| `e2e/` | Automated real-browser test: 3 accounts, invitations, waiting room, live call |
| `docs/` | [Architecture & costs](docs/ARCHITECTURE.md) · [Setup](docs/SETUP.md) · [Testing](docs/TESTING.md) · [Deployment](docs/DEPLOYMENT.md) |

Quick start: [docs/SETUP.md](docs/SETUP.md).

**Security note:** traffic is encrypted in transit (HTTPS, WSS, DTLS-SRTP).
ConnectCall is **not** end-to-end encrypted. See ARCHITECTURE.md §6.
