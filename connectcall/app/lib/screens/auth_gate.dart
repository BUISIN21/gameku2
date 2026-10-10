import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import 'home_screen.dart';
import 'login_screen.dart';

/// Shows the login screen when signed out and the home screen when signed in.
/// Signing out anywhere (or an expired session) automatically returns here.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, this.pendingInvite});

  /// Invitation opened before signing in; handled right after sign-in.
  final String? pendingInvite;

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    return StreamBuilder<User?>(
      stream: auth.userChanges,
      initialData: auth.currentUser,
      builder: (context, snap) {
        final user = snap.data;
        if (user == null) {
          // Pop any screens that were open for the previous user.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
          });
          return LoginScreen(hasInvite: pendingInvite != null);
        }
        return HomeScreen(key: ValueKey(user.uid), user: user, pendingInvite: pendingInvite);
      },
    );
  }
}
