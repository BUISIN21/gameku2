import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'screens/home_screen.dart';
import 'services/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsStore.load();
  // A web invitation link looks like https://<app>/?room=abcd-efgh-jkmn
  final invitedRoom = kIsWeb ? Uri.base.queryParameters['room'] : null;
  runApp(ConnectCallApp(settings: settings, invitedRoom: invitedRoom));
}

class ConnectCallApp extends StatelessWidget {
  const ConnectCallApp({super.key, required this.settings, this.invitedRoom});

  final SettingsStore settings;
  final String? invitedRoom;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: HomeScreen(settings: settings, invitedRoom: invitedRoom),
    );
  }
}
