# ConnectCall — Testing

## 1. Results so far (Phase 2)

Recorded on 2026-10-10 in a Linux build container, with Flutter 3.47.7, Node 22 and a
LiveKit server v1.13.8 built from source. **"Passed" means a command actually ran and
its output was checked. Nothing in this table is assumed.**

| # | Test | How | Result |
|---|---|---|---|
| 1 | Backend typecheck | `npm run typecheck` | ✅ passed |
| 2 | Backend unit/API tests (12): room creation, input validation, access key, token claims scoped to one room with no admin rights and TTL ≤ 600 s, unique server-issued identities, unknown/malformed/expired rooms refused identically, CORS allow-list, config validation without echoing secrets | `npm test` | ✅ 12/12 |
| 3 | Production build + start with pruned deps; `ws://` refused in production | `npm run build`, `npm prune --omit=dev`, `node dist/server.js` | ✅ passed |
| 4 | Flutter static analysis | `flutter analyze` | ✅ no issues |
| 5 | Flutter unit + widget tests (9): room-code parsing / invitation link, API client success + error + network failure, home-screen validation, link pre-fill | `flutter test` | ✅ 9/9 |
| 6 | Web release build | `flutter build web --release --no-web-resources-cdn` | ✅ built |
| 7 | **Real call, browser ↔ browser**: two Chromium instances with fake camera/mic join one room through the web build → backend → LiveKit | `e2e/two-browser-call.cjs` | ✅ 13/13 checks |
| 7a | … both participants publish camera + mic (server view) | | ✅ |
| 7b | … each browser renders local **and** remote video (`<video>` 1280×720 / 640×360, playing) | | ✅ |
| 7c | … each browser plays remote audio | | ✅ |
| 7d | … mute mic / camera off seen by server; unmute / camera on restores | | ✅ |
| 7e | … leave (with confirmation) removes participant | | ✅ |
| 7f | … unknown room code refused with a clear message, no LiveKit connection made | | ✅ |
| 8 | No server secrets in web build (`LIVEKIT_API_SECRET`, `devkey`, private keys) | `grep` over `build/web` | ✅ none found |
| 9 | Android APK build | GitHub Actions `ConnectCall` workflow (Android SDK downloads are blocked in the build container) | ⏳ see CI run |
| 10 | Android ↔ laptop call on a real phone | Manual, section 3 | ❌ **not yet tested** |
| 11 | Different networks (Wi-Fi ↔ mobile data) via LiveKit Cloud | Manual | ❌ not yet tested |
| 12 | Android permission denial / "don't ask again" flow | Manual | ❌ not yet tested |
| 13 | Front/rear camera switch on a phone | Manual | ❌ not yet tested |
| 14 | Network interruption + automatic reconnect | Manual | ❌ not yet tested |
| 15 | Laptop device picker with real multiple devices | Manual | ❌ not yet tested |
| 16 | Dockerfile build | `docker build` (no Docker daemon in container; the same steps were run by hand in #3) | ⚠️ not run |

## 2. Re-running the automated checks

```bash
# backend
cd connectcall/backend && npm ci && npm run typecheck && npm test

# app
cd connectcall/app && flutter pub get && flutter analyze && flutter test

# end-to-end (4 terminals)
livekit-server --dev --bind 127.0.0.1 --node-ip 127.0.0.1
cd connectcall/backend && LIVEKIT_URL=ws://localhost:7880 LIVEKIT_API_KEY=devkey LIVEKIT_API_SECRET=secret CORS_ORIGINS=http://localhost:5000 npm run dev
cd connectcall/app && flutter build web --release --no-web-resources-cdn && cd build/web && python3 -m http.server 5000
cd connectcall/e2e && npm install && npx playwright install chromium && npm test
```

Success: the last line is `13/13 checks passed`. Screenshots are saved in `e2e/screenshots/`.

## 3. Manual test plan (real devices)

### Set-up: two separate people / accounts

Phase 2 has no accounts: each device just types a different name. From Phase 3,
create **two Firebase accounts** (e.g. `tester.a@…` and `tester.b@…`) and sign
in with a different one on each device. Never share one account between two
devices, because LiveKit then treats them as the same identity and disconnects
the first ("You joined this meeting from another device").

### Set-up: different internet connections

Use LiveKit Cloud (SETUP.md Path B) and a backend that both devices can reach:

* Easiest: deploy the backend (DEPLOYMENT.md) so it has an HTTPS URL.
* Laptop on home Wi-Fi; phone with **Wi-Fi turned off**, on mobile data (4G/5G).
* For a third network, use a phone hotspot or a friend's connection.

### Checklist (copy, then fill in ✅/❌ + notes)

| # | Scenario | Steps | Expected |
|---|---|---|---|
| M1 | Android → laptop | Phone creates meeting, laptop joins by code | Both see + hear each other within ~5 s |
| M2 | Laptop → Android | Laptop creates, copies invite link, phone joins by code | Same as M1 |
| M3 | 3+ participants | Add a second browser / phone | Grid layout, everyone sees everyone |
| M4 | Different networks | Repeat M1 with phone on mobile data | Works; may take a few seconds longer |
| M5 | Mic / camera toggles | Toggle each on both sides | Other side sees muted icon / avatar |
| M6 | Switch camera (Android) | Tap ⟳ | Remote sees rear camera, then front again |
| M7 | Device picker (laptop) | ⚙ in call → choose other mic/camera/speaker | Switches without rejoining |
| M8 | Permission denied (Android) | Deny camera when asked | Joins with camera off, dialog explains; enabling later asks again |
| M9 | "Don't ask again" (Android) | Deny twice | Dialog offers **Open settings** |
| M10 | Permission blocked (browser) | Block camera in site settings | Dialog explains how to re-allow |
| M11 | No/busy device | Open camera in another app first (laptop) | "device is in use" message, call continues |
| M12 | Network drop | Turn Wi-Fi off for 5–10 s, then on | Top bar shows "Reconnecting…", then recovers |
| M13 | Long drop | Wi-Fi off for 60 s | "connection was lost" screen with **Rejoin** |
| M14 | Expired / wrong code | Join `aaaa-bbbb-cccc` | "does not exist or has expired" |
| M15 | Leave | Leave → confirm | Other side sees "X left", count drops |
| M16 | Back button (Android) | Press back during call | Leave confirmation appears |
| M17 | Secrets | `unzip -p app-release.apk \| strings \| grep -i -E "secret\|API[A-Za-z0-9]{10}"` | No LiveKit secret/key found |

Phase 3–5 add: login/logout, token expiry (revoke a session in Firebase console → next API call returns to login), expired/revoked invitations, unauthorized user opening a private room link, owner removing a participant, chat delivery and reconnection.
