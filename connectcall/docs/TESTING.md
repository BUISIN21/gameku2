# ConnectCall — Testing

**"Passed" means a command actually ran and its output was checked. Nothing in
these tables is assumed.** Manual results are recorded only when you report them.

## 1. Automated results (Phase 3)

Recorded on 2026-10-10 in a Linux build container: Flutter 3.47.7, Node 22,
Firebase emulators (firebase-tools 15.33), and a LiveKit server v1.13.8 built from source.

| # | Test | How | Result |
|---|---|---|---|
| 1 | Backend typecheck | `npm run typecheck` | ✅ |
| 2 | Backend API tests against **real Auth + Firestore emulators** (18): missing/forged/**revoked** ID tokens refused; profile validation; room creation; token scoped to one room, identity = Firebase uid, no admin rights, TTL ≤ 600 s; signed-in strangers get 404 for room/members/invites/waiting/token; invite accept → member; only owner can create/list/revoke invites; **revoked / expired / used-up** invites refused; **3 concurrent accepts of a 1-use invite → exactly 1 succeeds**; waiting room approve/deny; owner removes member → token refused, LiveKit kick, invite blocked; members can leave, owner cannot; only owner can end call; config never echoes secrets, production refuses `ws://` and emulator settings | `npm test` | ✅ 18/18 |
| 3 | **Firestore security rules** (8 tests, emulator): signed-out users read nothing; profiles readable, never client-writable; memberships private; rooms/members visible to members only; no client can create membership, change owner, or create rooms; waiting list visible to owner and requester only; invitations and block list never readable | `npm test` | ✅ 8/8 |
| 4 | Flutter static analysis | `flutter analyze` | ✅ no issues |
| 5 | Flutter unit + widget tests (13): invitation link parsing; API client sends ID token, **retries once with a refreshed token on 401, signs out after a second 401**, signed-out short-circuit, error mapping, network failure; login/registration validation; display-name rules match server | `flutter test` | ✅ 13/13 |
| 6 | Web release build | `flutter build web --release --no-web-resources-cdn` | ✅ |
| 7 | **End-to-end, three real browser users** (web build → backend → Firestore/Auth emulators → LiveKit) | `e2e/accounts-invites-call.cjs` | ✅ **22/22** |
| 7a | … registration signs in; invitation link survives sign-up and shows the inviter | | ✅ |
| 7b | … two accounts in one LiveKit room, identities = Firebase uids, names from profiles | | ✅ |
| 7c | … each browser renders both videos and plays the other's audio | | ✅ |
| 7d | … mute / camera-off reach the server and can be undone | | ✅ |
| 7e | … stranger refused (token, member list); member refused owner actions; unauthenticated refused | | ✅ |
| 7f | … owner removes a participant from inside the call → disconnected immediately, token refused afterwards | | ✅ |
| 7g | … revoked invitation link refused with a clear message | | ✅ |
| 7h | … waiting room: guest waits, owner approves, guest sees approval live (rules + Firestore listener) | | ✅ |
| 7i | … sign out returns to the login screen | | ✅ |
| 8 | No server secrets in the web build | `grep` for `LIVEKIT_API_SECRET`, `devkey`, private keys, `client_secret` | ✅ none |
| 9 | Android APK build (release + debug) with Firebase plugins; secret scan of APKs + web | GitHub Actions run 38030865700 (Android SDK downloads are blocked in this container) | ✅ |
| 10 | Backend + rules tests, Flutter tests and the 22-check E2E **also pass in CI** on a clean runner (LiveKit 1.13.8 release binary) | same run | ✅ |

**Found and fixed during testing:**
* The invitation-link dialog used `SelectableText`, which Flutter web doesn't expose to assistive technology. It's now plain text plus a Copy button.
* Release web builds against the **Auth emulator** lose the session on a full page reload. This is a FlutterFire limitation: it reconnects the emulator after reload only in debug builds. It doesn't affect real Firebase projects, but it is listed in SETUP.md troubleshooting, and the E2E test navigates inside the app instead of reloading.

Phase 2 results (still valid for the call screen): mute/camera toggles, leave with confirmation, and the Phase 2 web build were verified with a two-browser test (13/13). The APK built in CI after `permission_handler` was pinned to 12.0.3 (13.x requires compileSdk 37, which Flutter 3.47's Android Gradle Plugin doesn't support).

CI warns that `flutter_webrtc` and `livekit_client` still apply the Kotlin Gradle Plugin, and that a future Flutter release will stop building such plugins. Check for updated plugin versions before upgrading Flutter past 3.47.

## 2. Not yet tested (needs real devices or real services)

| # | Test | Status |
|---|---|---|
| 10a | Android ↔ laptop call on a real phone | ❌ not reported. You said "done" after Phase 2 but didn't say which checklist items passed |
| 11 | Different networks (Wi-Fi ↔ mobile data) via LiveKit Cloud | ❌ |
| 12 | Android permission denial / "don't ask again" | ❌ |
| 13 | Front/rear camera switch on a phone | ❌ |
| 14 | Network interruption + automatic reconnect | ❌ |
| 15 | Laptop device picker with real multiple devices | ❌ |
| 16 | Real Firebase project: sign-up e-mail, password reset e-mail, deployed rules + index | ❌ (only emulators so far) |
| 17 | Session revocation from the Firebase console while the app is open | ❌ (covered at API level in test #2) |
| 18 | Dockerfile build | ⚠️ not run (no Docker daemon here; the same steps were run by hand) |

## 3. Re-running the automated checks

```bash
# backend + security rules (starts the emulators itself; needs Java 21)
cd connectcall/backend && npm ci && npm run typecheck && npm test

# app
cd connectcall/app && flutter pub get && flutter analyze && flutter test

# end-to-end (5 terminals)
cd connectcall/backend && npm run emulators
livekit-server --dev --bind 127.0.0.1 --node-ip 127.0.0.1
cd connectcall/backend && npm run build && PORT=8080 LIVEKIT_URL=ws://localhost:7880 LIVEKIT_API_KEY=devkey \
  LIVEKIT_API_SECRET=secret FIREBASE_PROJECT_ID=demo-connectcall FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
  FIRESTORE_EMULATOR_HOST=127.0.0.1:8085 CORS_ORIGINS=http://localhost:5000 node dist/server.js
cd connectcall/app && flutter build web --release --no-web-resources-cdn --dart-define-from-file=config/emulator.json \
  && cd build/web && python3 -m http.server 5000 --bind 127.0.0.1
cd connectcall/e2e && npm ci && npx playwright install chromium && npm test
```

Success: the last line is `22/22 checks passed`. Screenshots are saved in `e2e/screenshots/`.
CI runs all of this on every push (`.github/workflows/connectcall.yml`, job `e2e`).

## 4. Manual test plan (real devices)

### Two separate accounts

Create **two accounts** (e.g. `tester.a@…` on the laptop and `tester.b@…` on the
phone). Never use one account on two devices in the same call: LiveKit treats
them as the same person and disconnects the first ("You joined this meeting from
another device"). To test as a third person, use a browser Incognito window with a third account.

### Different internet connections

Use LiveKit Cloud and a backend both devices can reach (deploy it, DEPLOYMENT.md):

* Laptop on home Wi-Fi; phone with **Wi-Fi turned off**, on mobile data.
* For a third network, use a phone hotspot or a friend's connection.

### Checklist (copy, then fill in ✅/❌ + notes, and tell me the results)

| # | Scenario | Steps | Expected |
|---|---|---|---|
| M1 | Android → laptop | Phone (A) creates room + link, laptop (B) opens link, signs up, accepts, both join | See + hear each other within ~5 s |
| M2 | Laptop → Android | Laptop creates room + link, phone pastes link in **Join with an invitation** | Same as M1 |
| M3 | 3+ participants | Add an Incognito window with a third account | Grid layout, everyone sees everyone |
| M4 | Different networks | Repeat M1 with phone on mobile data | Works; may take a few seconds longer |
| M5 | Mic / camera toggles | Toggle each on both sides | Other side sees muted icon / avatar |
| M6 | Switch camera (Android) | Tap ⟳ | Remote sees rear camera, then front again |
| M7 | Device picker (laptop) | Sliders icon in call → choose other mic/camera/speaker | Switches without rejoining |
| M8 | Permission denied (Android) | Deny camera when asked | Joins with camera off, dialog explains; enabling later asks again |
| M9 | "Don't ask again" (Android) | Deny twice | Dialog offers **Open settings** |
| M10 | Permission blocked (browser) | Block camera in site settings | Dialog explains how to re-allow |
| M11 | Busy device | Open the camera in another app first (laptop) | "device is in use" message, call continues |
| M12 | Network drop | Turn Wi-Fi off for 5–10 s, then on | Top bar shows "Reconnecting…", then recovers |
| M13 | Long drop | Wi-Fi off for 60 s | "connection was lost" screen with **Rejoin** |
| M14 | Expired invitation | Create a 1-hour link, open it 61+ minutes later | "This invitation has expired" |
| M15 | Revoked invitation | Owner cancels a link, guest opens it | "cancelled by the owner" |
| M16 | Unauthorized access | Third account opens the room without an invitation (e.g. try an old, used-up link) | Refused; no call access |
| M17 | Remove participant | Owner → People → remove guest | Guest is disconnected and the room disappears from their list |
| M18 | Waiting room | Room with waiting room on; guest asks; owner approves / declines | Guest gets in / sees "did not let you in" |
| M19 | Logout | Profile → Sign out | Login screen; back button doesn't return to rooms |
| M20 | Session revoked | Firebase console → Authentication → user → ⋮ → *Disable account* while the app is open, then act | Next action signs the user out with a message |
| M21 | Back button (Android) | Press back during a call | Leave confirmation appears |
| M22 | Secrets | `unzip -p app-release.apk \| strings \| grep -i -E "LIVEKIT_API_SECRET\|private_key"` | Nothing found |
