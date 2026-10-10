# ConnectCall — Deployment

Target setup: **backend on Google Cloud Run** (HTTPS, scales to zero), **web app on
Firebase Hosting**, **Firestore + Auth** in the same Firebase project, **LiveKit Cloud** for media.
Phase 5 adds release signing, monitoring and notifications.

Before you start, finish SETUP.md Path B (Firebase project, rules deployed, LiveKit keys).

## 1. Google Cloud basics (once)

```bash
gcloud auth login
gcloud config set project YOUR_FIREBASE_PROJECT_ID     # the Firebase project is a Google Cloud project
gcloud services enable run.googleapis.com secretmanager.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com
```

The project must be on the **Blaze** (pay-as-you-go) plan to use Cloud Run. Right away, set a
**budget alert** (Billing → Budgets & alerts, e.g. US$5), because Blaze has no hard spending cap.

## 2. A dedicated service account with only the rights it needs

```bash
gcloud iam service-accounts create connectcall-api --display-name "ConnectCall API"
SA=connectcall-api@YOUR_FIREBASE_PROJECT_ID.iam.gserviceaccount.com
# read/write Firestore documents
gcloud projects add-iam-policy-binding YOUR_FIREBASE_PROJECT_ID --member "serviceAccount:$SA" --role roles/datastore.user
# verify ID tokens incl. revocation checks (reads user records, cannot change them)
gcloud projects add-iam-policy-binding YOUR_FIREBASE_PROJECT_ID --member "serviceAccount:$SA" --role roles/firebaseauth.viewer
```

No key file is created or downloaded. Cloud Run runs the service *as* this account.

## 3. Store the LiveKit secret in Secret Manager

Type this in your own terminal. Don't save it in a script or a file:

```bash
printf '%s' 'PASTE-LIVEKIT-API-SECRET' | gcloud secrets create livekit-api-secret --data-file=-
gcloud secrets add-iam-policy-binding livekit-api-secret --member "serviceAccount:$SA" --role roles/secretmanager.secretAccessor
```

## 4. Deploy the backend

From `connectcall/backend` (Cloud Build uses the Dockerfile):

```bash
gcloud run deploy connectcall-api --source . --region europe-west1 \
  --service-account "$SA" --allow-unauthenticated \
  --set-env-vars NODE_ENV=production,TRUST_PROXY=1,FIREBASE_PROJECT_ID=YOUR_FIREBASE_PROJECT_ID,LIVEKIT_URL=wss://YOUR.livekit.cloud,LIVEKIT_API_KEY=APIxxxx,CORS_ORIGINS=https://YOUR_FIREBASE_PROJECT_ID.web.app \
  --set-secrets LIVEKIT_API_SECRET=livekit-api-secret:latest
```

* `--allow-unauthenticated` means "reachable from the internet". The API checks the Firebase ID token on every `/api` request itself.
* The backend keeps no state in memory, so you can run several instances.
* The command prints `Service URL: https://connectcall-api-xxxx.run.app`. Check it with `curl https://connectcall-api-xxxx.run.app/healthz` → `{"status":"ok"}`.

Any Docker host (Render, Fly.io, Railway, a VPS behind Caddy/Nginx with TLS) works too: build the
Dockerfile, set the variables from `.env.example`, and give it Google credentials for the project
(Workload Identity Federation preferred over a key file).

## 5. Deploy the web app to Firebase Hosting

Create `connectcall/app/config/prod.json` (git-ignored) from `dev.json`, with:

```json
"API_BASE_URL": "https://connectcall-api-xxxx.run.app",
"WEB_APP_URL": "https://YOUR_FIREBASE_PROJECT_ID.web.app"
```

```bash
cd connectcall/app
flutter build web --release --no-web-resources-cdn --dart-define-from-file=config/prod.json
cd ..
npx --prefix backend firebase deploy --only hosting,firestore:rules,firestore:indexes
```

It prints `Hosting URL: https://YOUR_FIREBASE_PROJECT_ID.web.app`. `firebase.json` already
serves `app/build/web`, rewrites all paths to the app (so invitation links work), and sets
security headers.

If you use a custom domain, add it in **Authentication → Settings → Authorized domains** and to
the backend's `CORS_ORIGINS`.

## 6. Android APK

```bash
cd connectcall/app
flutter build apk --release --dart-define-from-file=config/prod.json
```

The file is `build/app/outputs/flutter-apk/app-release.apk`. It is signed with the debug key,
which is fine for side-loading but must be replaced with your own upload key before you publish to
Google Play (Phase 5).

## 7. Updating

* Backend: run the same `gcloud run deploy` again. Cloud Run switches traffic only after the new revision starts.
* Rules / indexes: `firebase deploy --only firestore:rules,firestore:indexes`. Rules take effect within a minute.
* Web: rebuild, then `firebase deploy --only hosting`. You can roll back in the console (Hosting → release history).
