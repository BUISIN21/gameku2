# ConnectCall — Setup (Phase 3: accounts, private rooms, invitations)

By the end of this guide two people with their own accounts can be in the same
private video call, one on an Android phone and one in a laptop browser.

There are two ways to run everything:

* **Path A — fully local, no accounts anywhere.** Firebase runs in local emulators and LiveKit in dev mode. Good for development and for checking that everything works. Works for browser windows on one laptop (and the Android *emulator*).
* **Path B — real services.** A Firebase project plus LiveKit Cloud. Needed for a real phone, other networks, and other people.

---

## 0. Install the tools (once)

| Tool | Version used | Check with |
|---|---|---|
| Flutter SDK | 3.47.x stable (Dart 3.13) | `flutter --version` |
| Android Studio (Android SDK + platform tools) | current | `flutter doctor` |
| JDK | 17 for Android builds; **21** for the Firebase emulators | `java -version` |
| Node.js | 22 LTS (20+ works) | `node -v` |
| Google Chrome or Edge | current | — |
| Google Cloud CLI (Path B only) | current | `gcloud --version` |

```bash
flutter doctor
```

Success looks like `[✓] Flutter`, `[✓] Android toolchain`, `[✓] Chrome`. If it says
`Android license status unknown`, run `flutter doctor --android-licenses` and accept everything.

Install the backend's packages (this also installs the Firebase CLI used below):

```bash
cd connectcall/backend
npm ci
```

---

## Path A — everything local (5 minutes)

Use four terminals.

**Terminal 1: Firebase emulators** (Auth + Firestore with the real security rules)

```bash
cd connectcall/backend
npm run emulators
```

Wait for `✔  All emulators ready!`.

**Terminal 2: LiveKit in dev mode**

```bash
# install once:  brew install livekit   |   curl -sSL https://get.livekit.io | bash
livekit-server --dev
```

Wait for `starting LiveKit server {"portHttp": 7880 ...}`. Dev mode uses key `devkey` and secret `secret`; use them only on your own machine.

**Terminal 3: backend**

```bash
cd connectcall/backend
cp .env.example .env
```

Edit `.env`:

```ini
LIVEKIT_URL=ws://localhost:7880
LIVEKIT_API_KEY=devkey
LIVEKIT_API_SECRET=secret
FIREBASE_PROJECT_ID=demo-connectcall
FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
FIRESTORE_EMULATOR_HOST=127.0.0.1:8085
CORS_ORIGINS=http://localhost:5000
```

```bash
npm run dev
```

Success: `"emulators":true,"msg":"ConnectCall API listening"`.

**Terminal 4: web app**

```bash
cd connectcall/app
flutter pub get
flutter run -d chrome --web-port 5000 --dart-define-from-file=config/emulator.json
```

Then try it (section 4 below) with one normal Chrome window and one Incognito window, each with its own account.

Accounts and data live only in the emulators and disappear when Terminal 1 stops.

---

## Path B — real Firebase project + LiveKit Cloud

### B1. LiveKit Cloud

1. Sign up at https://cloud.livekit.io and create a project (e.g. `connectcall-dev`).
2. **Settings → Keys → Create key**. Note the **WebSocket URL** (`wss://…livekit.cloud`), **API key** (`API…`) and **API secret**. Keep the secret private: never put it in the app, in `config/*.json`, or in a commit.

### B2. Firebase project

1. https://console.firebase.google.com → **Add project**. Google Analytics is not needed.
2. **Build → Authentication → Get started → Sign-in method → Email/Password → Enable → Save.**
3. **Build → Firestore Database → Create database** → *Start in production mode* → choose a location near your users. The location can't be changed later.
4. Deploy the security rules and indexes from this repo:

   ```bash
   cd connectcall
   npx --prefix backend firebase login
   npx --prefix backend firebase use --add      # pick your project, alias "default"
   npx --prefix backend firebase deploy --only firestore:rules,firestore:indexes
   ```

   Success: `✔  Deploy complete!`. The composite index takes a few minutes to build.
5. **Project settings (gear icon) → General → Your apps**:
   * Click **</>** (Web) → nickname `ConnectCall web` → **Register app**. Copy `apiKey`, `authDomain`, `projectId`, `storageBucket`, `messagingSenderId` and `appId`.
   * Click the **Android** icon → package name **`app.connectcall.connectcall`** → **Register app**. You do **not** need to download `google-services.json`. Note the Android **App ID** (`1:…:android:…`).
6. Create `connectcall/app/config/dev.json` (git-ignored) from `config/example.json`:

   ```json
   {
     "APP_NAME": "ConnectCall",
     "API_BASE_URL": "http://localhost:8080",
     "FIREBASE_API_KEY": "AIza…",
     "FIREBASE_PROJECT_ID": "your-project-id",
     "FIREBASE_MESSAGING_SENDER_ID": "1234…",
     "FIREBASE_AUTH_DOMAIN": "your-project-id.firebaseapp.com",
     "FIREBASE_STORAGE_BUCKET": "your-project-id.firebasestorage.app",
     "FIREBASE_WEB_APP_ID": "1:1234…:web:…",
     "FIREBASE_ANDROID_APP_ID": "1:1234…:android:…"
   }
   ```

   These values are **not secrets**: Firebase puts them in every app by design, and access is enforced by sign-in, security rules and the backend. Still, restrict the key: Google Cloud console → **APIs & Services → Credentials** → your "Browser key" → limit it to your web domains and to the *Identity Toolkit*, *Token Service* and *Cloud Firestore* APIs.

### B3. Backend against the real project

The backend reads Firebase with your Google identity. No key file is needed.

```bash
gcloud auth application-default login     # opens a browser; sign in with the Firebase project owner
cd connectcall/backend
cp .env.example .env
```

Edit `.env` (no emulator lines):

```ini
LIVEKIT_URL=wss://connectcall-dev-abc123.livekit.cloud
LIVEKIT_API_KEY=API…
LIVEKIT_API_SECRET=…
FIREBASE_PROJECT_ID=your-project-id
CORS_ORIGINS=http://localhost:5000
```

```bash
npm run dev
```

Success: `"firebaseProject":"your-project-id","emulators":false,"msg":"ConnectCall API listening"`.

### B4. Web app on the laptop

```bash
cd connectcall/app
flutter run -d chrome --web-port 5000 --dart-define-from-file=config/dev.json
```

### B5. Android phone

The phone must reach the backend. For a first test, put the laptop and the phone on the **same Wi-Fi**:

1. Find the laptop's LAN IP: `ipconfig` (Windows), `ipconfig getifaddr en0` (macOS) or `hostname -I` (Linux). Example: `192.168.1.20`.
2. Allow incoming connections on port 8080 in the laptop firewall.
3. Copy `config/dev.json` to `config/phone.json` and set `"API_BASE_URL": "http://192.168.1.20:8080"`.
4. Enable **Developer options → USB debugging** on the phone, plug it in, and check that `flutter devices` lists it.
5. Run a **debug** build (only debug builds may use plain `http://`):

   ```bash
   flutter run -d <device-id> --dart-define-from-file=config/phone.json
   ```

For a phone on mobile data, deploy the backend to HTTPS first (DEPLOYMENT.md).

---

## 4. Using the app (two people)

1. **Person A** (laptop): **New here? Create an account** → name, e-mail, password (8+ characters).
2. A: **New room** → name it → optionally turn on **Waiting room** → **Create**.
3. A: under *Invitations*, **New link** → choose how long it works and for how many people → **Create link** → **Copy**. Send it to B by e-mail, chat, etc.
4. **Person B** opens the link in a browser, or on Android pastes it into **Join with an invitation → Open**. B creates an account and taps **Accept invitation** (or **Ask to join** if the waiting room is on; A then taps ✓ under *Waiting room*).
5. Both tap **Join call** and allow camera + microphone.
6. A (owner) can: **People** icon in the call → remove someone, or **End call for everyone**; on the room page: cancel invitation links and remove members.
7. Sign out: avatar (top right) → **Sign out**.

---

## 5. Building installable files

```bash
flutter build apk --release --dart-define-from-file=config/prod.json
flutter build web --release --no-web-resources-cdn --dart-define-from-file=config/prod.json
```

`prod.json` is like `dev.json`, but `API_BASE_URL` must be your **HTTPS** backend and `WEB_APP_URL` your web address (so Android shares proper links).

| Output | Location |
|---|---|
| Release APK (needs an HTTPS API) | `connectcall/app/build/app/outputs/flutter-apk/app-release.apk` |
| Debug APK (`flutter build apk --debug`, allows http:// for LAN tests) | `connectcall/app/build/app/outputs/flutter-apk/app-debug.apk` |
| Web bundle (upload the whole folder) | `connectcall/app/build/web/` |

The release APK contains all CPU types (~90 MB). `--split-per-abi` makes ~30 MB files, and most modern phones need `app-arm64-v8a-release.apk`.

**No Android SDK?** GitHub Actions builds both. Add a repository **variable** (not a secret) called `CONNECTCALL_APP_CONFIG` whose value is the contents of your `prod.json` (Settings → Secrets and variables → Actions → **Variables**). Then download `ConnectCall-android` / `ConnectCall-web` from the latest **Actions → ConnectCall** run.

To install an APK, copy it to the phone, open it, and allow "Install unknown apps" for your file manager.

---

## 6. Configuration reference

| Setting | Where | Default |
|---|---|---|
| App name | `APP_NAME` in the config JSON (+ `android/app/src/main/res/values/strings.xml` for the launcher label) | `ConnectCall` |
| API address | `API_BASE_URL`, or Profile → Advanced in the app | web `http://localhost:8080`, Android emulator `http://10.0.2.2:8080` |
| Invitation link base (Android) | `WEB_APP_URL` | empty: Android shares the bare invitation id, which can be pasted into the app |
| Firebase project | `FIREBASE_*` values | none: the app shows a setup message |
| Local emulators | `USE_FIREBASE_EMULATOR=true` (`config/emulator.json`), `FIREBASE_EMULATOR_HOST` to override the host | off |

---

## 7. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| App shows "This build has no Firebase configuration" | Run/build with `--dart-define-from-file=config/<file>.json` |
| "E-mail sign-in is not enabled for this project" | Step B2.2 was skipped |
| "Could not reach the server" | Wrong `API_BASE_URL`, backend not running, firewall blocks 8080, or the phone is not on the same Wi-Fi |
| Signed out with "Your session was ended" | Session revoked (password change, account disabled, or "revoke" in Firebase console): sign in again |
| Backend: `Could not load the default credentials` | Run `gcloud auth application-default login` (B3) |
| Backend: `PERMISSION_DENIED` from Firestore | The Google account used in B3 has no access to the project, or `FIREBASE_PROJECT_ID` is wrong |
| Backend: `FAILED_PRECONDITION: The query requires an index` | Indexes not deployed or still building (B2.4) |
| Room list stays empty / "Could not load your rooms" | Rules not deployed (B2.4), or offline |
| Works in debug APK, not in release APK | Release builds reject `http://`; deploy the API on HTTPS |
| Web page loses sign-in after reload, **only with emulators in a release build** | FlutterFire reconnects to the Auth emulator after a reload only in debug builds. Use `flutter run` (debug) with emulators. Real projects are not affected |
| No camera prompt / "Permission was denied" | The page is not on HTTPS/localhost, or access was blocked earlier. Click the camera icon in the address bar → Allow |
| "The device is in use by another app" | Close Zoom/Teams/other tabs using the camera |
| Other person's video stays black | Network blocks UDP. LiveKit Cloud falls back to TCP/TURN; local dev mode has no TURN |
| CORS error in the browser console | Add the exact web origin (scheme + host + port) to `CORS_ORIGINS` |
| "You joined this meeting from another device" | The same account joined on a second device; one account = one connection per call |
