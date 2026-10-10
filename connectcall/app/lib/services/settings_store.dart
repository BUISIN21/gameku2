import 'package:shared_preferences/shared_preferences.dart';

import '../core/config.dart';

/// Remembers non-sensitive conveniences between launches.
class SettingsStore {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<SettingsStore> load() async => SettingsStore(await SharedPreferences.getInstance());

  String get displayName => _prefs.getString('displayName') ?? '';
  set displayName(String v) => _prefs.setString('displayName', v);

  String get serverUrl => _prefs.getString('serverUrl') ?? AppConfig.defaultApiBaseUrl;
  set serverUrl(String v) => _prefs.setString('serverUrl', v);

  /// Phase 2 room-creation key. This is a shared, low-value key that gates
  /// who may create rooms on a test server; it is replaced by real accounts
  /// in Phase 3. It is stored in plain app preferences, not compiled in.
  String get accessKey => _prefs.getString('accessKey') ?? '';
  set accessKey(String v) => _prefs.setString('accessKey', v);
}
