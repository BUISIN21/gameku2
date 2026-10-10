# ConnectCall — Architecture

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
| `permission_handler` 12.0.3 | Explicit Android runtime prompts so we can explain a refusal | Only called on Android; browsers show their own prompt. **Pinned below 13**: 13.x needs Android compileSdk 37, which Flutter 3.47's Android Gradle Plugin (9.1) does not support yet (found by the CI APK build) |
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
│   ├── config/                  example.json, emulator.json (+ your git-ignored dev/prod.json)
│   ├── lib/
│   │   ├── core/                config, Firebase setup, app scope, theme
│   │   ├── models/              models.dart, join_info.dart, invite_link.dart
│   │   ├── services/            api_client, auth_service, media_permissions, settings_store
│   │   ├── screens/             auth_gate, login, home, room, invite, profile, meeting
│   │   ├── widgets/             participant_tile, control_bar, device_settings_sheet, common
│   │   └── main.dart
│   ├── android/                 manifest with camera/mic permissions, ProGuard rules
│   ├── web/                     index.html, manifest.json
│   └── test/                    unit + widget tests
├── backend/
│   ├── src/
│   │   ├── config/env.ts        zod-validated environment
│   │   ├── middleware/          auth (Firebase ID tokens), errors, rate limits
│   │   ├── routes/              me.ts, rooms.ts, invites.ts, validation.ts
│   │   ├── services/            rooms.ts (all permission logic), livekit.ts, firebase.ts
│   │   ├── app.ts / server.ts
│   ├── test/                    API tests + security-rules tests (run on emulators)
│   ├── .env.example             placeholders only
│   └── Dockerfile
├── firebase/                    firestore.rules, firestore.indexes.json
├── firebase.json / .firebaserc  Firebase CLI config (emulators, rules, hosting)
├── e2e/                         real-browser end-to-end test
└── docs/                        ARCHITECTURE, SETUP, TESTING, DEPLOYMENT
```

### Data model (Firestore)

| Path | Contents | Who can read (rules) | Who writes |
|---|---|---|---|
| `users/{uid}` | `displayName`, `photoUrl` | any signed-in user | backend |
| `users/{uid}/memberships/{roomId}` | `roomName`, `role` | that user | backend |
| `rooms/{roomId}` | `name`, `ownerUid`, `ownerName`, `requireApproval` | members | backend |
| `rooms/{roomId}/members/{uid}` | `displayName`, `role` | members; a user can read their own doc | backend |
| `rooms/{roomId}/waiting/{uid}` | join requests | owner; the requester | backend |
| `rooms/{roomId}/blocked/{uid}` | removed users | nobody | backend |
| `invites/{inviteId}` | `roomId`, `expiresAt`, `maxUses`, `uses`, `revoked` | nobody | backend |

All writes that grant access go through the backend. Clients only *read*, and the rules allow exactly
the reads in the table, which drive the live room list, member list and waiting room.

### API (all routes require `Authorization: Bearer <Firebase ID token>`)

| Method & path | Who |
|---|---|
| `GET /api/me`, `PUT /api/me/profile` | self |
| `POST /api/rooms` | any user (max 50 owned rooms) |
| `GET /api/rooms/:id`, `GET /api/rooms/:id/members`, `POST /api/rooms/:id/token` | members |
| `DELETE /api/rooms/:id/members/me` | members (leave) |
| `DELETE /api/rooms/:id/members/:uid`, `POST /api/rooms/:id/end` | owner |
| `GET/POST /api/rooms/:id/invites`, `POST /api/rooms/:id/invites/:inviteId/revoke` | owner |
| `GET /api/rooms/:id/waiting`, `POST /api/rooms/:id/waiting/:uid/approve\|deny` | owner |
| `GET /api/invites/:id`, `POST /api/invites/:id/accept` | anyone holding the link |

## 3. Flows

### Authentication flow (implemented in Phase 3)

1. The app signs in with Firebase Authentication (email/password; Google sign-in can be added later).
2. The Firebase SDK keeps a refresh token and gives the app an **ID token** (a JWT, valid 1 hour, refreshed automatically).
3. Every API call sends `Authorization: Bearer <ID token>`.
4. The API verifies it with the Firebase Admin SDK (`verifyIdToken(token, checkRevoked=true)`), which checks the signature, expiry, audience and revocation. The verified `uid` is the only identity the server trusts.
5. A 401 makes the app refresh the ID token once, and send the user back to the login screen if that fails (expired or revoked session).
6. Logout calls `FirebaseAuth.signOut()`. The auth gate closes every open screen, including a call, and shows the login screen.

### Invitation flow (implemented in Phase 3)

1. The owner creates a room → `rooms/{roomId}` in Firestore with `ownerUid`. Every room is private.
2. The owner creates an invitation → the API stores `invites/{inviteId}` with a random 128-bit id, `roomId`, `expiresAt` (e.g. 24 h), `maxUses`, `revoked: false`. Link: `https://<web-app>/?invite=<inviteId>`.
3. The recipient opens the link and signs in. The app calls `POST /api/invites/{id}/accept`.
4. In one Firestore **transaction** the server checks that the invite exists and is not expired, revoked, used up or blocked for this user. It then adds the user to `rooms/{roomId}/members/{uid}` (or `waiting/` when approval is on) and counts the use. Concurrent requests cannot exceed `maxUses`.
5. Revoking sets `revoked: true`. Existing members keep access until removed. Removing someone deletes their membership, adds them to `blocked/` (so old links stop working for them) and calls LiveKit `removeParticipant`.

### LiveKit token flow

1. The app asks `POST /api/rooms/{roomId}/token` with its ID token.
2. The server verifies the ID token and checks that `rooms/{roomId}/members/{uid}` exists.
3. The server mints a JWT signed with the LiveKit API secret: `identity` = Firebase uid, `name` from the profile, and a grant for **that room only** (`roomJoin`, publish/subscribe, data). The token has no admin rights and a TTL of 10 minutes.
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
* Every API request needs a Firebase ID token, verified with revocation checking. Disabled accounts and revoked sessions are refused immediately.
* Every request body is validated with strict schemas. Unknown fields are rejected, and names are length- and character-restricted.
* Least privilege: Firestore rules give clients read-only access to exactly what they need. All access-granting writes run server-side, with permission checks in one place (`services/rooms.ts`).
* Rate limits: 300 req/min per IP overall; per user, 20 room creations per 10 min, 30 tokens per min, 30 invite views/accepts per min.
* Invitation ids carry 128 random bits, expire (1 h – 7 days), are limited in uses (1–100) and can be revoked.
* Participant identity in calls is the verified Firebase uid, so a client cannot impersonate another user.
* Non-members get the same 404 for existing and non-existing rooms, so the API doesn't reveal which rooms exist.
* Logs never include headers, bodies or tokens. Production refuses `ws://` and emulator settings.

### Encryption: what is and is not claimed

* **Transport encryption: yes.** The API uses HTTPS. LiveKit signalling uses WSS (TLS). Media uses WebRTC's mandatory DTLS-SRTP. Nobody on the network path (Wi-Fi owner, ISP) can read or alter the audio/video.
* **End-to-end encryption: no (not implemented).** The SFU decrypts SRTP to route packets, so LiveKit's servers technically handle unencrypted media. LiveKit offers an E2EE mode (shared-key frame encryption), and the Flutter SDK supports it on Android and on web browsers with insertable streams. Doing it properly needs a key-distribution design and per-platform testing. **ConnectCall must not be described as end-to-end encrypted** unless that is built and verified.

## 7. Known technical limitations

* Profile pictures are set as an `https://` image URL. Uploading photos needs Cloud Storage, which now requires the paid Blaze plan, so it is deferred.
* E-mail verification is not enforced yet; anyone can register with any address (they still need an invitation to join a room).
* One account = one connection per call. Joining from a second device disconnects the first.
* A room owner cannot leave or transfer ownership yet, and rooms cannot be deleted from the app yet.
* Web release builds pointed at the **Auth emulator** forget the session on reload (FlutterFire limitation; real projects are not affected).
* Browsers only allow camera access on **HTTPS or `localhost`**. A laptop opening `http://192.168.x.x` will not get a camera.
* Android release builds require **HTTPS/WSS**. The debug build allows `http://` for LAN testing.
* Incoming-call ringing while the app is closed needs FCM + a full-screen notification (Phase 5). Android restricts background starts, so ringing behaviour varies by manufacturer.
* iOS is out of scope (it would need an Apple developer account and CallKit work).
* The web app needs a modern Chromium browser, Firefox or Safari. Device selection for speakers works in Chromium-based browsers. Firefox/Safari may not list audio outputs.

## 8. Implementation plan

| Phase | Deliverable | Status |
|---|---|---|
| 1 | This document | ✅ |
| 2 | Create/join room, real A/V, mic/cam/switch-camera/device picker/leave, status + duration, reconnect + error handling. Backend token API with tests. CI builds APK + web | ✅ web↔web call verified with real browsers; **Android device results not yet reported** |
| 3 | Firebase Auth (register/login/logout/reset/profile), ID-token-verified API, private rooms, expiring + revocable + use-limited invitations, waiting room, owner remove / end-for-all, Firestore rules | ✅ verified on emulators: 26 backend/rules tests, 13 Flutter tests, 22-check 3-user browser E2E; **real Firebase project and devices not yet tested** |
| 4 | Chat (Firestore, room-scoped), contacts / friends via invitation, recent conversations, group-call polish, 1:1 "call a contact" | next |
| 5 | FCM call notifications, release signing, Secret Manager, Cloud Run + Firebase Hosting deploy, structured logging | |
| 6 | Full device/network test matrix with recorded results | |
