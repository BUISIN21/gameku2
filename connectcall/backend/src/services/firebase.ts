import { applicationDefault, getApps, initializeApp, type App } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

/**
 * Initialises the Firebase Admin SDK.
 *
 * On Google Cloud (Cloud Run) credentials come from the service account the
 * service runs as; locally they come from `gcloud auth application-default
 * login`. Against the emulators no credentials are needed. A service-account
 * JSON key file is never required and should not be created.
 */
export function initFirebase(projectId: string) {
  const usingEmulators = Boolean(process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST);
  const app: App =
    getApps()[0] ??
    initializeApp(usingEmulators ? { projectId } : { projectId, credential: applicationDefault() });
  const db = getFirestore(app);
  return { auth: getAuth(app), db };
}
