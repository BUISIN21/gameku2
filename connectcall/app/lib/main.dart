import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/app_scope.dart';
import 'core/config.dart';
import 'core/firebase_setup.dart';
import 'core/theme.dart';
import 'models/invite_link.dart';
import 'screens/auth_gate.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/settings_store.dart';

/// Used to show "session expired" from anywhere, including outside widgets.
final messengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final options = FirebaseSetup.options;
  if (options == null) {
    runApp(const _MissingConfigApp());
    return;
  }
  await FirebaseSetup.initialize(options);
  final settings = await SettingsStore.load();
  final auth = AuthService(FirebaseAuth.instance);

  // A web invitation link looks like https://<app>/?invite=<id>
  final pendingInvite = kIsWeb ? InviteLink.parse(Uri.base.toString()) : null;

  final api = ApiClient(
    baseUrl: () => settings.serverUrl,
    token: auth.idToken,
    onSessionExpired: (message) async {
      if (auth.currentUser == null) return;
      await auth.signOut();
      messengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$message You have been signed out.')));
    },
  );

  runApp(AppScope(
    settings: settings,
    auth: auth,
    api: api,
    firestore: FirebaseFirestore.instance,
    child: ConnectCallApp(pendingInvite: pendingInvite),
  ));
}

class ConnectCallApp extends StatelessWidget {
  const ConnectCallApp({super.key, this.pendingInvite});

  final String? pendingInvite;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: messengerKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: AuthGate(pendingInvite: pendingInvite),
    );
  }
}

class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'This build has no Firebase configuration.\n\n'
              'Build with --dart-define-from-file=config/<your-file>.json '
              '(see config/example.json and docs/SETUP.md), or use '
              'config/emulator.json for local development.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
