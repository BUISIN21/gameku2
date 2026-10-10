import 'package:flutter/foundation.dart';

/// Build-time configuration, set with `--dart-define=KEY=value`.
///
/// Nothing here is secret: every value is compiled into the app and can be
/// read by anyone who has the APK or the web bundle.
class AppConfig {
  AppConfig._();

  /// Product name shown in the UI. Change with `--dart-define=APP_NAME=...`.
  static const appName = String.fromEnvironment('APP_NAME', defaultValue: 'ConnectCall');

  static const _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Base URL of the ConnectCall backend, without a trailing slash.
  ///
  /// Defaults are for local development: the Android emulator reaches the
  /// host machine at 10.0.2.2. Real phones need the laptop's LAN IP or a
  /// deployed HTTPS URL, passed with `--dart-define=API_BASE_URL=...`.
  static String get defaultApiBaseUrl {
    if (_apiBaseUrl.isNotEmpty) return _stripSlash(_apiBaseUrl);
    if (kIsWeb) return 'http://localhost:8080';
    return 'http://10.0.2.2:8080';
  }

  static String _stripSlash(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;
}

/// Public URL of the deployed web app (e.g. `https://connectcall.web.app`),
/// used to build shareable invitation links from the Android app. When empty,
/// the web app uses its own address and Android shares the bare room code.
const webAppUrl = String.fromEnvironment('WEB_APP_URL');

/// Builds the link a user can send to invite someone to [roomCode].
String? invitationLink(String roomCode) {
  String base;
  if (webAppUrl.isNotEmpty) {
    base = webAppUrl;
  } else if (kIsWeb) {
    base = Uri.base.replace(query: '', fragment: '').toString().replaceAll(RegExp(r'\?$'), '');
  } else {
    return null;
  }
  return Uri.parse(base).replace(queryParameters: {'room': roomCode}).toString();
}
