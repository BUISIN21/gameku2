import 'package:shared_preferences/shared_preferences.dart';

import '../core/config.dart';

/// Remembers non-sensitive conveniences between launches.
class SettingsStore {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<SettingsStore> load() async => SettingsStore(await SharedPreferences.getInstance());

  /// Lets testers point a build at another backend without rebuilding.
  String get serverUrl => _prefs.getString('serverUrl') ?? AppConfig.defaultApiBaseUrl;
  set serverUrl(String v) => _prefs.setString('serverUrl', v);
}
