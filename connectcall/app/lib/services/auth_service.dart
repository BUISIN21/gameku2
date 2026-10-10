import 'package:firebase_auth/firebase_auth.dart';

/// Thin wrapper over Firebase Authentication with user-friendly errors.
class AuthService {
  AuthService(this._auth);

  final FirebaseAuth _auth;

  Stream<User?> get userChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<void> signIn(String email, String password) => _guard(() async {
        await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
      });

  Future<void> register({required String email, required String password, required String displayName}) =>
      _guard(() async {
        final cred = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
        await cred.user?.updateDisplayName(displayName.trim());
        // Refresh so the next ID token carries the display name.
        await cred.user?.getIdToken(true);
      });

  Future<void> sendPasswordReset(String email) => _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  Future<void> signOut() => _auth.signOut();

  /// The current Firebase ID token (refreshed automatically when it is about
  /// to expire), or null when signed out.
  Future<String?> idToken({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      return await user.getIdToken(forceRefresh);
    } on FirebaseAuthException {
      return null; // refresh token revoked / user disabled
    }
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(messageFor(e.code));
    }
  }

  static String messageFor(String code) => switch (code) {
        'invalid-email' => 'That e-mail address is not valid.',
        'user-disabled' => 'This account has been disabled.',
        'user-not-found' || 'wrong-password' || 'invalid-credential' || 'INVALID_LOGIN_CREDENTIALS' =>
          'Wrong e-mail or password.',
        'email-already-in-use' => 'An account with this e-mail already exists. Try signing in.',
        'weak-password' => 'Choose a stronger password (at least 8 characters).',
        'too-many-requests' => 'Too many attempts. Wait a few minutes and try again.',
        'network-request-failed' => 'No connection. Check your internet and try again.',
        'operation-not-allowed' => 'E-mail sign-in is not enabled for this project (see docs/SETUP.md).',
        _ => 'Sign-in failed ($code).',
      };
}

class AuthFailure implements Exception {
  AuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
