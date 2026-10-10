import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase configuration, supplied at build time with `--dart-define` or
/// `--dart-define-from-file=config/<name>.json` (see config/example.json).
///
/// These values identify the Firebase project to the client SDK. They are NOT
/// secrets: they ship inside every app and web page by design. Access is
/// protected by Firebase Authentication, Firestore Security Rules and the
/// backend, not by hiding these values.
class FirebaseSetup {
  FirebaseSetup._();

  static const _useEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR');
  static const _emulatorHost = String.fromEnvironment('FIREBASE_EMULATOR_HOST');

  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const _authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const _storageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
  static const _webAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const _androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');

  static bool get usingEmulator => _useEmulator;

  /// Null when the build is missing configuration; the app then shows setup help.
  static FirebaseOptions? get options {
    if (_useEmulator) {
      // `demo-*` projects run entirely in the local emulators; no real project needed.
      return const FirebaseOptions(
        apiKey: 'demo-api-key',
        appId: '1:000000000000:web:0000000000000000',
        messagingSenderId: '000000000000',
        projectId: 'demo-connectcall',
        authDomain: 'demo-connectcall.firebaseapp.com',
      );
    }
    final appId = kIsWeb ? _webAppId : _androidAppId;
    if (_apiKey.isEmpty || _projectId.isEmpty || appId.isEmpty || _senderId.isEmpty) return null;
    return FirebaseOptions(
      apiKey: _apiKey,
      appId: appId,
      messagingSenderId: _senderId,
      projectId: _projectId,
      authDomain: _authDomain.isEmpty ? null : _authDomain,
      storageBucket: _storageBucket.isEmpty ? null : _storageBucket,
    );
  }

  static Future<void> initialize(FirebaseOptions options) async {
    await Firebase.initializeApp(options: options);
    if (_useEmulator) {
      final host = _emulatorHost.isNotEmpty ? _emulatorHost : (kIsWeb ? 'localhost' : '10.0.2.2');
      await FirebaseAuth.instance.useAuthEmulator(host, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(host, 8085);
    }
  }
}
