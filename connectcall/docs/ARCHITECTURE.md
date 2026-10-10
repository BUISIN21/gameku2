# ConnectCall — Phase 1: Architecture

## 1. System overview

```
 ┌──────────────────────┐        HTTPS (REST, JSON)        ┌────────────────────────────┐
 │ Flutter app          │ ───────────────────────────────▶ │ ConnectCall API            │
 │  • Android APK       │   1. create / join room          │ Node.js + TypeScript       │
 │  • Web (Chrome/Edge) │ ◀─────────────────────────────── │ (Cloud Run / any host)     │
 │                      │   2. short-lived LiveKit token   │  • validates input         │
 │                      │                                  │  • rate limits             │
 │                      │                                  │  • owns LiveKit API secret │
 │                      │                                  └─────────────┬──────────────┘
 │                      │                                                │ Phase 3+: Firebase Admin
 │                      │                                                ▼
 │                      │                                  ┌────────────────────────────┐
 │                      │  Phase 3+: sign in, chat,        │ Firebase                   │
 │                      │ ◀──── profiles (rules-checked) ─▶│  • Authentication          │
 │                      │                                  │  • Cloud Firestore         │
 │                      │                                  │  • Cloud Messaging (FCM)   │
 │                      │                                  └────────────────────────────┘
 │                      │   3. WSS signalling +            ┌────────────────────────────┐
 │                      │      WebRTC media (DTLS-SRTP)    │ LiveKit Cloud (SFU)        │
 │                      │ ◀──────────────────────────────▶ │  • routes audio/video      │
 └──────────────────────┘   UDP, TCP or TURN/TLS fallback  │  • built-in STUN/TURN      │
                                                           └────────────────────────────┘
```

* **The client never sees a secret.** It only receives a LiveKit JWT that lets
  one identity join one room for a few minutes.
* **LiveKit Cloud is an SFU** (Selective Forwarding Unit). Each participant
  uploads one stream and LiveKit forwards it to everyone else. This makes
  group calls work on phones, where a peer-to-peer mesh would overload the
  upload link. It also bundles STUN/TURN, so calls cross strict NATs and
  mobile carriers without running our own TURN server.
* **The backend is stateless in Phase 3+.** Room metadata, invitations and
  membership move to Firestore so the API can run several instances.

### Why this stack

| Choice | Reason | Compatibility check |
|---|---|---|
| Flutter 3.47 (Dart 3.13) | One codebase for Android + web | Verified: `flutter build web` passes here; APK built by CI |
| `livekit_client` 2.13.1 | Official Flutter SDK; Android + web supported | Uses `flutter_webrtc` 1.6; minSdk 21 (Flutter default 24 is above that) |
| `permission_handler` 13 | Explicit Android runtime prompts so we can explain a refusal | Only called on Android; browsers show their own prompt |
| Node 22 + Express 5 + TS 5.9 | Simple, well-understood API server | Verified: typecheck, tests, build pass |
| `livekit-server-sdk` 2.19 | Official token minting / room admin | Node ≥ 19 |
| Firebase Auth + Firestore + FCM | Managed identity, rules-enforced DB, push | FlutterFire supports Android + web (Phase 3) |

**Known incompatibility handled:** Flutter web by default loads CanvasKit from
Google's CDN (`gstatic.com`). Corporate networks and some regions block it, so
the web build uses `--no-web-resources-cdn` to self-host it.

## 2. Directory structure

```
connectcall/
├── app/                         Flutter app (Android + web)
│   ├── lib/
│   │   ├── core/                config.dart (APP_NAME, API URL), theme.dart
│   │   ├── models/              join_info.dart, room_code.dart
│   │   ├── services/            api_client.dart, media_permissions.dart, settings_store.dart
│   │   ├── screens/             home_screen.dart, meeting_screen.dart
│   │   ├── widgets/             participant_tile.dart, control_bar.dart, device_settings_sheet.dart
│   │   └── main.dart
│   ├── android/                 manifest with camera/mic permissions, ProGuard rules
│   ├── web/                     index.html, manifest.json
│   └── test/                    unit + widget tests
├── backend/
│   ├── src/
│   │   ├── config/env.ts        zod-validated environment
│   │   ├── middleware/          errors, rate limiting, access key
│   │   ├── routes/rooms.ts      POST /api/rooms, POST /api/rooms/:code/join
│   │   ├── services/            livekit.ts (tokens), roomStore.ts
│   │   ├── app.ts / server.ts
│   ├── test/rooms.test.ts
│   ├── .env.example             placeholders only
│   └── Dockerfile
├── e2e/two-browser-call.cjs     real two-browser call test
├── firebase/                    (Phase 3) firestore.rules, firestore.indexes.json
└── docs/                        ARCHITECTURE, SETUP, TESTING, DEPLOYMENT
```

## 3. Flows

### Authentication flow (Phase 3)

1. The app signs in with Firebase Authentication (email/password, optionally Google).
2. The Firebase SDK keeps a refresh token and gives the app an **ID token** (a JWT, valid 1 hour, refreshed automatically).
3. Every API call sends `Authorization: Bearer <ID token>`.
4. The API verifies it with the Firebase Admin SDK (`verifyIdToken(token, checkRevoked=true)`), which checks the signature, expiry, audience and revocation. The verified `uid` is the only identity the server trusts.
5. A 401 makes the app refresh the ID token once, and send the user back to the login screen if that fails (expired or revoked session).
6. Logout calls `FirebaseAuth.signOut()`, disconnects any call and clears cached data.

### Invitation flow (Phase 3)

1. The owner creates a room → `rooms/{roomId}` in Firestore, `ownerUid`, `private: true`.
2. The owner creates an invitation → the API stores `invites/{inviteId}` with a random 128-bit id, `roomId`, `expiresAt` (e.g. 24 h), `maxUses`, `revoked: false`. Link: `https://<web-app>/?invite=<inviteId>`.
3. The recipient opens the link and signs in. The app calls `POST /api/invites/{id}/accept`.
4. The server checks that the invite exists, is not expired or revoked, and still has uses left. It then adds the user to `rooms/{roomId}/members/{uid}` (or to `waiting/` if approval is on).
5. Revoking sets `revoked: true`. Existing members keep access until removed, and the owner can remove them, which also calls LiveKit `removeParticipant`.

### LiveKit token flow (all phases)

1. The app asks `POST /api/rooms/{room}/join`.
2. The server checks permission. In Phase 2 that means the room exists and has not expired; in Phase 3+ the caller must also be a member.
3. The server mints a JWT signed with the LiveKit API secret: `identity` (the server-chosen guest id, or the Firebase uid from Phase 3), `name`, a grant for **that room only** (`roomJoin`, publish/subscribe, data). The token has no admin rights and a TTL of 10 minutes.
4. The app connects to LiveKit with the token. While connected, LiveKit refreshes the session itself, so a short TTL does not cut off long calls.
5. Removing someone is done server-side through the LiveKit RoomService API. The client cannot do it.

## 4. Accounts you need

| Service | Why | Plan to start on |
|---|---|---|
| **LiveKit Cloud** (cloud.livekit.io) | Media server + TURN | Free "Build" plan |
| **Google Firebase** (console.firebase.google.com) | Auth, Firestore, FCM, Hosting | Spark (free) to start. Blaze (pay-as-you-go) is needed for Cloud Run / Cloud Functions / Secret Manager |
| **Google Cloud** (same project as Firebase) | Cloud Run for the API, Secret Manager | Pay-as-you-go with free tier |
| **GitHub** | Code + CI builds the APK and web bundle | Free |
| Google Play Console (optional, later) | Publishing to Play Store | One-time US$25 registration |

## 5. Realistic cost estimate

Prices below come from published third-party summaries dated 2026. The official pricing
pages could not be fetched from the build environment, so **check
livekit.io/pricing, firebase.google.com/pricing and cloud.google.com/run/pricing
before you commit money.**

**How LiveKit bills:** one *participant-minute* is one person connected for one
minute. A 30-minute call with 2 people = 60 minutes; with 4 people = 120.

| Item | Free allowance (as reported) | Paid tier |
|---|---|---|
| LiveKit Cloud "Build" | ~5,000 WebRTC participant-minutes / month, limited concurrency | "Ship" ≈ US$50/month, ~150,000 minutes, then ≈ US$0.0005/min |
| Firebase Auth (email / Google) | Free for typical consumer volumes (sources say 50k MAU) | — |
| Firestore | 50k reads, 20k writes, 20k deletes per day, 1 GiB stored | Per-operation pricing on Blaze |
| Firebase Hosting (web app) | 10 GB storage; transfer allowance varies by source | Per-GB on Blaze |
| FCM push | Free | — |
| Cloud Run (API) | ~2M requests, 180k vCPU-s, 360k GiB-s / month | Per-use beyond |

**What this means in practice**

| Usage | Participant-min / month | Expected cost |
|---|---|---|
| You + a few friends testing (10 calls × 30 min × 2 people) | 600 | **US$0** |
| Small group (50 calls × 45 min × 3 people) | 6,750 | Over the free LiveKit tier → **≈ US$50/month** (Ship plan); Firebase/Cloud Run still ≈ US$0 |
| Early public beta (1,000 calls × 30 min × 2) | 60,000 | **≈ US$50/month** + a few dollars of Firebase |

Set a **budget alert** in Google Cloud Billing (e.g. US$5) as soon as you switch to Blaze,
because Blaze has no automatic hard spending cap.

## 6. Security model

* LiveKit API secret and Firebase Admin credentials exist only on the server (env vars locally, Secret Manager in production).
* Every request body is validated with strict schemas. Unknown fields are rejected and display names are length- and character-restricted.
* Rate limits: 120 req/min per IP overall, 20 room creations per 10 min, 30 joins per min (code guessing becomes impractical, since codes carry ~59 bits of entropy).
* The server chooses participant identities, so a client cannot impersonate another user.
* Logs never include headers, bodies or tokens.
* Unknown, malformed and expired room codes all return the same error, so the API does not reveal which codes exist.

### Encryption: what is and is not claimed

* **Transport encryption: yes.** The API uses HTTPS. LiveKit signalling uses WSS (TLS). Media uses WebRTC's mandatory DTLS-SRTP. Nobody on the network path (Wi-Fi owner, ISP) can read or alter the audio/video.
* **End-to-end encryption: no (not implemented).** The SFU decrypts SRTP to route packets, so LiveKit's servers technically handle unencrypted media. LiveKit offers an E2EE mode (shared-key frame encryption), and the Flutter SDK supports it on Android and on web browsers with insertable streams. Doing it properly needs a key-distribution design and per-platform testing. **ConnectCall must not be described as end-to-end encrypted** unless that is built and verified.

## 7. Known technical limitations

* Phase 2 keeps rooms in memory: a backend restart forgets active room codes (calls already in progress continue). Run a single instance until Phase 3.
* Phase 2 has no accounts. Anyone holding a valid room code can join, so share codes only with intended people. Room creation can be gated with `CREATE_ROOM_KEY`.
* Browsers only allow camera access on **HTTPS or `localhost`**. A laptop opening `http://192.168.x.x` will not get a camera.
* Android release builds require **HTTPS/WSS**. The debug build allows `http://` for LAN testing.
* Incoming-call ringing while the app is closed needs FCM + a full-screen notification (Phase 5). Android restricts background starts, so ringing behaviour varies by manufacturer.
* iOS is out of scope (it would need an Apple developer account and CallKit work).
* The web app needs a modern Chromium browser, Firefox or Safari. Device selection for speakers works in Chromium-based browsers. Firefox/Safari may not list audio outputs.

## 8. Implementation plan

| Phase | Deliverable | Status |
|---|---|---|
| 1 | This document | ✅ |
| 2 | Create/join room, real A/V, mic/cam/switch-camera/device picker/leave, status + duration, reconnect + error handling. Backend token API with tests. CI builds APK + web | ✅ code complete; web↔web call verified with real browsers; **Android device test pending (you)** |
| 3 | Firebase Auth (register/login/logout/profile), ID-token-verified API, Firestore rooms + invitations (expiring, revocable), membership checks, Firestore rules | next |
| 4 | Group-call layout polish, chat (Firestore, room-scoped), participant list, owner remove/end-for-all, waiting room | |
| 5 | FCM call notifications, release signing, Secret Manager, Cloud Run + Firebase Hosting deploy, structured logging | |
| 6 | Full device/network test matrix with recorded results | |
