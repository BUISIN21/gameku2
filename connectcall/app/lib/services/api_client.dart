import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/join_info.dart';
import '../models/models.dart';

/// An error the UI can show directly to the user.
class ApiException implements Exception {
  ApiException(this.code, this.message, {this.status});

  final String code;
  final String message;
  final int? status;

  bool get isAuthError => status == 401;

  @override
  String toString() => message;
}

typedef TokenProvider = Future<String?> Function({bool forceRefresh});

/// Client for the ConnectCall backend. Every request carries the user's
/// Firebase ID token. A 401 is retried once with a freshly minted token; if
/// that still fails the session is over and [onSessionExpired] is called.
class ApiClient {
  ApiClient({
    required this._baseUrl,
    required this._token,
    required this._onSessionExpired,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String Function() _baseUrl;
  final TokenProvider _token;
  final void Function(String message) _onSessionExpired;
  final http.Client _http;
  static const _timeout = Duration(seconds: 15);

  String get baseUrl => _baseUrl();

  // ------------------------------------------------------------- profile
  Future<Profile> me() async => Profile.fromJson(await _send('GET', '/api/me'));

  Future<Profile> updateProfile({required String displayName, String? photoUrl}) async => Profile.fromJson(
      await _send('PUT', '/api/me/profile', {'displayName': displayName, 'photoUrl': photoUrl}));

  // ------------------------------------------------------------- rooms
  Future<String> createRoom({required String name, required bool requireApproval}) async =>
      (await _send('POST', '/api/rooms', {'name': name, 'requireApproval': requireApproval}))['id'] as String;

  Future<RoomDetails> room(String roomId) async => RoomDetails.fromJson(await _send('GET', '/api/rooms/$roomId'));

  Future<JoinInfo> joinToken(String roomId) async => JoinInfo.fromJson(await _send('POST', '/api/rooms/$roomId/token'));

  Future<void> endCallForEveryone(String roomId) => _send('POST', '/api/rooms/$roomId/end');

  Future<void> removeMember(String roomId, String uid) => _send('DELETE', '/api/rooms/$roomId/members/$uid');

  Future<void> leaveRoom(String roomId) => _send('DELETE', '/api/rooms/$roomId/members/me');

  // ------------------------------------------------------------- invitations
  Future<List<Invite>> invites(String roomId) async {
    final body = await _send('GET', '/api/rooms/$roomId/invites');
    return (body['invites'] as List).map((e) => Invite.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Invite> createInvite(String roomId, {required int expiresInHours, required int maxUses}) async =>
      Invite.fromJson(await _send(
          'POST', '/api/rooms/$roomId/invites', {'expiresInHours': expiresInHours, 'maxUses': maxUses}));

  Future<void> revokeInvite(String roomId, String inviteId) =>
      _send('POST', '/api/rooms/$roomId/invites/$inviteId/revoke');

  Future<InvitePreview> previewInvite(String inviteId) async =>
      InvitePreview.fromJson(await _send('GET', '/api/invites/$inviteId'));

  Future<(String roomId, AcceptResult)> acceptInvite(String inviteId) async {
    final body = await _send('POST', '/api/invites/$inviteId/accept');
    return (body['roomId'] as String, body['status'] == 'waiting' ? AcceptResult.waiting : AcceptResult.member);
  }

  // ------------------------------------------------------------- waiting room
  Future<void> decide(String roomId, String uid, {required bool approve}) =>
      _send('POST', '/api/rooms/$roomId/waiting/$uid/${approve ? 'approve' : 'deny'}');

  // ------------------------------------------------------------- transport
  Future<Map<String, dynamic>> _send(String method, String path, [Map<String, dynamic>? json]) async {
    var res = await _once(method, path, json, forceRefresh: false);
    if (res.statusCode == 401) res = await _once(method, path, json, forceRefresh: true);
    return _decode(res);
  }

  Future<http.Response> _once(String method, String path, Map<String, dynamic>? json,
      {required bool forceRefresh}) async {
    final token = await _token(forceRefresh: forceRefresh);
    if (token == null) {
      _onSessionExpired('Please sign in again.');
      throw ApiException('unauthenticated', 'Please sign in again.', status: 401);
    }
    final req = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json';
    if (json != null) req.body = jsonEncode(json);
    try {
      return await http.Response.fromStream(await _http.send(req).timeout(_timeout));
    } on TimeoutException {
      throw ApiException('timeout', 'The server took too long to answer. Check your connection and try again.');
    } catch (_) {
      throw ApiException('network', 'Could not reach the server. Check your internet connection.');
    }
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode == 204) return const {};
    Map<String, dynamic>? decoded;
    try {
      decoded = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    if (res.statusCode >= 200 && res.statusCode < 300 && decoded != null) return decoded;

    final error = decoded?['error'];
    final code = error is Map ? error['code'] as String? ?? 'error' : 'http_${res.statusCode}';
    final message = error is Map ? error['message'] as String? : null;
    final friendly = _friendly(code, message ?? 'Unexpected server response (${res.statusCode}).');
    if (res.statusCode == 401) _onSessionExpired(friendly);
    throw ApiException(code, friendly, status: res.statusCode);
  }

  static String _friendly(String code, String fallback) => switch (code) {
        'rate_limited' => 'Too many attempts. Wait a minute and try again.',
        'room_not_found' => 'This room does not exist or you are no longer a member.',
        _ => fallback,
      };
}
