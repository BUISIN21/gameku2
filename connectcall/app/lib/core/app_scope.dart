import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/settings_store.dart';

/// Makes the app-wide services available to every screen.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.settings,
    required this.auth,
    required this.api,
    required this.firestore,
    required super.child,
  });

  final SettingsStore settings;
  final AuthService auth;
  final ApiClient api;
  final FirebaseFirestore firestore;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing above $context');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}
