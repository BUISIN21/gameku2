# ConnectCall — Deployment (Phase 2 level)

This deploys what exists today. Phase 5 adds Secret Manager wiring
for Firebase, release signing and monitoring.

## Backend → Google Cloud Run

Cloud Run gives the API an HTTPS URL, which release APKs and browsers require. It scales to zero when idle.

1. Install the Google Cloud CLI and run `gcloud init`. Pick (or create) a project and enable billing. Set a budget alert at US$5.
2. Store the LiveKit secret in **Secret Manager** (never in a file):

   ```bash
   gcloud services enable run.googleapis.com secretmanager.googleapis.com cloudbuild.googleapis.com
   printf '%s' 'PASTE-LIVEKIT-API-SECRET' | gcloud secrets create livekit-api-secret --data-file=-
   ```

   (Type the command in your own terminal; don't save it in a script.)

3. Deploy from the `connectcall/backend` folder (Cloud Build uses the Dockerfile):

   ```bash
   gcloud run deploy connectcall-api --source . --region europe-west1 \
     --allow-unauthenticated --max-instances 1 \
     --set-env-vars NODE_ENV=production,TRUST_PROXY=1,LIVEKIT_URL=wss://YOUR.livekit.cloud,LIVEKIT_API_KEY=APIxxxx,CORS_ORIGINS=https://YOUR-WEB-APP \
     --set-secrets LIVEKIT_API_SECRET=livekit-api-secret:latest
   ```

   * `--allow-unauthenticated` means "reachable from the internet". The app's own checks do the access control.
   * `--max-instances 1` is required in Phase 2 because rooms live in memory. Remove it after Phase 3.
   * Grant the Cloud Run service account the **Secret Manager Secret Accessor** role on that secret if the deploy says it lacks access.

4. The command prints `Service URL: https://connectcall-api-xxxx.run.app`. Check it:
   `curl https://connectcall-api-xxxx.run.app/healthz` → `{"status":"ok"}`.

Any Docker host (Render, Fly.io, Railway, a VPS behind Caddy/Nginx with TLS) works the same way: build the Dockerfile and set the variables from `.env.example`.

## Web app → Firebase Hosting

```bash
npm install -g firebase-tools
firebase login
cd connectcall/app
flutter build web --release --no-web-resources-cdn \
  --dart-define=API_BASE_URL=https://connectcall-api-xxxx.run.app
firebase init hosting     # public directory: build/web, single-page app: Yes, GitHub deploys: No
firebase deploy --only hosting
```

It prints `Hosting URL: https://YOUR-PROJECT.web.app`. Add that exact origin to the
backend's `CORS_ORIGINS` and redeploy the backend.

## Android APK

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://connectcall-api-xxxx.run.app \
  --dart-define=WEB_APP_URL=https://YOUR-PROJECT.web.app
```

The file is `build/app/outputs/flutter-apk/app-release.apk`. Phase 2 signs it with the debug
key. That is fine for side-loading, but it must be replaced with your own upload key
before you publish to Google Play (Phase 5).
