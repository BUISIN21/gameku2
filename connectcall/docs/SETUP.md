# ConnectCall — Setup (Phase 2: basic working video call)

By the end of this guide an Android phone and a laptop browser will be in the same video call.

There are two ways to run the media server:

* **Path A — fully local, no accounts.** Best for checking that everything runs. Browser-only on one laptop.
* **Path B — LiveKit Cloud.** Needed for a phone ↔ laptop call, and for calls across different networks.

---

## 0. Install the tools (once)

| Tool | Version used | Check with |
|---|---|---|
| Flutter SDK | 3.47.x stable (Dart 3.13) | `flutter --version` |
| Android Studio (gives the Android SDK + platform tools) | current | `flutter doctor` |
| JDK | 17 | `java -version` |
| Node.js | 22 LTS (20+ works) | `node -v` |
| Google Chrome or Edge | current | — |

Run:

```bash
flutter doctor
```

Success looks like `[✓] Flutter`, `[✓] Android toolchain`, `[✓] Chrome`. If the
Android toolchain shows `✗ Android license status unknown`, run
`flutter doctor --android-licenses` and accept everything.

---

## 1. Get LiveKit credentials

### Path A: local dev server (no account)

```bash
# macOS
brew install livekit
# Linux
curl -sSL https://get.livekit.io | bash
# or Docker (any OS)
docker run --rm -p 7880:7880 -p 7881:7881 -p 7882:7882/udp livekit/livekit-server --dev --bind 0.0.0.0
```

Start it (skip if you used Docker):

```bash
livekit-server --dev
```

You should see `starting LiveKit server  {"portHttp": 7880 ...}`. Dev mode uses
API key `devkey` and secret `secret`. **Use these only on your own machine.**

### Path B: LiveKit Cloud (free plan)

1. Go to https://cloud.livekit.io and sign up.
2. Create a project (any name, e.g. `connectcall-dev`).
3. Open **Settings → Keys** (or **API keys**) → **Create key**.
4. Copy three things somewhere private, **not** into any file inside the repo:
   * **WebSocket URL**: looks like `wss://connectcall-dev-abc123.livekit.cloud`
   * **API Key**: starts with `API...`
   * **API Secret**: long random string. It is shown only once; treat it like a password.

---

## 2. Run the backend

```bash
cd connectcall/backend
npm ci
cp .env.example .env
```

Edit `.env` (this file is git-ignored, so it never gets committed):

```ini
# Path A
LIVEKIT_URL=ws://localhost:7880
LIVEKIT_API_KEY=devkey
LIVEKIT_API_SECRET=secret

# Path B: paste your own values
# LIVEKIT_URL=wss://connectcall-dev-abc123.livekit.cloud
# LIVEKIT_API_KEY=API...
# LIVEKIT_API_SECRET=...

CORS_ORIGINS=http://localhost:5000
```

Check, test and start:

```bash
npm run typecheck   # no output = OK
npm test            # ends with: # pass 12  # fail 0
npm run dev         # development server with auto-reload
```

Success looks like:

```
{"level":30,...,"port":8080,"livekitUrl":"wss://...","roomCreationKeyRequired":false,"msg":"ConnectCall API listening"}
```

Check in a second terminal:

```bash
curl http://localhost:8080/healthz
# {"status":"ok"}
curl -X POST http://localhost:8080/api/rooms -H 'Content-Type: application/json' -d '{"displayName":"Test"}'
# {"roomCode":"abcd-efgh-jkmn","expiresAt":"..."}
```

Production build: `npm run build && npm start` (runs `dist/server.js`).

---

## 3. Run the web app on the laptop

```bash
cd connectcall/app
flutter pub get
flutter run -d chrome --web-port 5000
```

Chrome opens `http://localhost:5000`. The API address defaults to `http://localhost:8080`.

1. Type your name → **New meeting**.
2. Chrome asks for camera + microphone → **Allow**.
3. You see yourself and the text "Waiting for others to join…". The top bar shows the room code (e.g. `k7mz-q2wp-hx4d`).
4. Open a **second Chrome window** (or an Incognito window) at `http://localhost:5000`, type another name, paste the code, then click **Join**. Both windows should now show two video tiles.

> Camera access only works on `https://` or `http://localhost`. To use the web
> app from a *different* laptop, deploy it to HTTPS (see DEPLOYMENT.md).

---

## 4. Run on an Android phone (Path B)

The phone must reach the backend. For a first test, run the backend on your
laptop and connect both devices to **the same Wi-Fi**.

1. Find the laptop's LAN IP address: `ipconfig` (Windows), `ipconfig getifaddr en0` (macOS) or `hostname -I` (Linux). Example: `192.168.1.20`.
2. Allow incoming connections on port 8080 in the laptop firewall.
3. On the phone, enable **Developer options → USB debugging** and plug it in. `flutter devices` should list it.
4. Run a **debug** build (debug builds are allowed to use plain `http://`):

```bash
cd connectcall/app
flutter run -d <device-id> --dart-define=API_BASE_URL=http://192.168.1.20:8080
```

5. On the phone: type a name → **Join** with the code from the laptop → allow Camera and Microphone.
6. Both screens show two people. Try mute, camera off, switch camera (phone), the device picker (laptop) and leave.

You can also change the server address inside the app with the ⚙ icon on the
home screen.

### Building installable files

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://your-api.example.com
flutter build web --release --no-web-resources-cdn --dart-define=API_BASE_URL=https://your-api.example.com
```

| Output | Location |
|---|---|
| Release APK (needs an HTTPS API) | `connectcall/app/build/app/outputs/flutter-apk/app-release.apk` |
| Debug APK (`flutter build apk --debug`, allows http:// for LAN tests) | `connectcall/app/build/app/outputs/flutter-apk/app-debug.apk` |
| Web bundle (upload the whole folder) | `connectcall/app/build/web/` |

**No Android SDK?** GitHub Actions builds both for you. Push to GitHub, open
**Actions → ConnectCall → latest run → Artifacts**, and download
`ConnectCall-android` / `ConnectCall-web`. To bake your API address into those
builds, add the repository variable `CONNECTCALL_API_BASE_URL` (Settings →
Secrets and variables → Actions → **Variables**). It is a public URL, not a secret.

The release APK contains all CPU types (~90 MB). `flutter build apk --release --split-per-abi` makes ~30 MB files, and most modern phones need `app-arm64-v8a-release.apk`.

To install an APK, copy it to the phone, open it and allow "Install unknown apps" for your file manager.

---

## 5. Configuration reference

| Setting | Where | Default |
|---|---|---|
| App name | `--dart-define=APP_NAME=...` (+ `android/app/src/main/res/values/strings.xml` for the launcher label) | `ConnectCall` |
| API address | `--dart-define=API_BASE_URL=...` or ⚙ in the app | web: `http://localhost:8080`, Android: `http://10.0.2.2:8080` (emulator) |
| Invitation link base for Android | `--dart-define=WEB_APP_URL=https://...` | empty (Android shares the bare code) |
| Room-creation key | backend `CREATE_ROOM_KEY`, typed into ⚙ in the app | off |

---

## 6. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| "Could not reach the server at …" | Wrong API address, backend not running, laptop firewall blocks 8080, or phone on mobile data instead of the same Wi-Fi |
| Works in debug APK, not in release APK | Release builds reject `http://`. Deploy the API on HTTPS |
| Browser shows no camera prompt / "Permission was denied" | Page is not on HTTPS/localhost, or access was blocked earlier. Click the camera icon in the address bar → Allow, then reload |
| "The device is in use by another app" | Close Zoom/Teams/other tabs using the camera |
| Joins but other person's video stays black | Network blocks UDP. LiveKit Cloud falls back to TCP/TURN automatically; the local dev server (Path A) has no TURN, so use Path B across networks |
| Backend exits with `Invalid configuration: LIVEKIT_API_KEY` | `.env` missing or misspelled. Compare with `.env.example` |
| Browser console: CORS error | Add the exact web origin (scheme + host + port) to `CORS_ORIGINS` |
| "That meeting does not exist or has expired" | Wrong code, room older than `ROOM_TTL_MINUTES`, or backend restarted (Phase 2 keeps rooms in memory) |
| Phone audio comes out of the earpiece | Turn the volume up during the call. The app requests loudspeaker output, but some phones override this while a Bluetooth headset is connected |
