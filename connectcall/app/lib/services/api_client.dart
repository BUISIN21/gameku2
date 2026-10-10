import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/join_info.dart';

/// An error the UI can show directly to the user.
class ApiException implements Exception {
  ApiException(this.code, this.message, {this.status});

  final String code;
  final String message;
  final int? status;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient(this.baseUrl, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _http;
  static const _timeout = Duration(seconds: 15);

  /// Creates a new room and returns its code.
  Future<String> createRoom({required String displayName, String? accessKey}) async {
    final body = await _post(
      '/api/rooms',
      {'displayName': displayName},
      headers: {if (accessKey != null && accessKey.isNotEmpty) 'X-Access-Key': accessKey},
    );
    return body['roomCode'] as String;
  }

  /// Asks the backend for permission to join [roomCode]. On success the
  /// result holds a short-lived LiveKit token for that room only.
  Future<JoinInfo> joinRoom({required String roomCode, required String displayName}) async {
    final body = await _post('/api/rooms/${Uri.encodeComponent(roomCode)}/join', {'displayName': displayName});
    return JoinInfo.fromJson(body);
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> json, {Map<String, String>? headers}) async {
    final http.Response res;
    try {
      res = await _http
          .post(
            Uri.parse('$baseUrl$path'),
            headers: {'Content-Type': 'application/json', ...?headers},
            body: jsonEncode(json),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw ApiException('timeout', 'The server took too long to answer. Check your connection and try again.');
    } catch (_) {
      throw ApiException(
        'network',
        'Could not reach the server at $baseUrl. Check your internet connection and the server address.',
      );
    }

    Map<String, dynamic>? decoded;
    try {
      decoded = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      decoded = null;
    }

    if (res.statusCode >= 200 && res.statusCode < 300 && decoded != null) return decoded;

    final error = decoded?['error'];
    if (error is Map<String, dynamic>) {
      throw ApiException(
        error['code'] as String? ?? 'error',
        _friendly(error['code'] as String?, error['message'] as String?),
        status: res.statusCode,
      );
    }
    throw ApiException('http_${res.statusCode}', 'Unexpected server response (${res.statusCode}).',
        status: res.statusCode);
  }

  static String _friendly(String? code, String? fallback) => switch (code) {
        'room_not_found' => 'That meeting does not exist or has expired. Check the code with the person who invited you.',
        'rate_limited' => 'Too many attempts. Wait a minute and try again.',
        'invalid_access_key' => 'The access key is missing or wrong.',
        _ => fallback ?? 'Something went wrong.',
      };
}
