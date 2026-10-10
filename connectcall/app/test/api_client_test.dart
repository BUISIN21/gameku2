import 'dart:convert';

import 'package:connectcall/models/models.dart';
import 'package:connectcall/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late List<bool> refreshes;
  late List<String> expired;

  ApiClient client(MockClientHandler handler, {String? token = 'tok'}) {
    refreshes = [];
    expired = [];
    return ApiClient(
      baseUrl: () => 'https://api.test',
      token: ({bool forceRefresh = false}) async {
        refreshes.add(forceRefresh);
        return token == null ? null : (forceRefresh ? '$token-fresh' : token);
      },
      onSessionExpired: expired.add,
      httpClient: MockClient(handler),
    );
  }

  test('sends the Firebase ID token and JSON body', () async {
    late http.Request sent;
    final api = client((req) async {
      sent = req;
      return http.Response(jsonEncode({'id': 'room123'}), 201);
    });
    final id = await api.createRoom(name: 'Family', requireApproval: true);
    expect(id, 'room123');
    expect(sent.method, 'POST');
    expect(sent.url.toString(), 'https://api.test/api/rooms');
    expect(sent.headers['Authorization'], 'Bearer tok');
    expect(jsonDecode(sent.body), {'name': 'Family', 'requireApproval': true});
  });

  test('retries once with a refreshed token after a 401', () async {
    final seen = <String?>[];
    final api = client((req) async {
      seen.add(req.headers['Authorization']);
      if (req.headers['Authorization'] == 'Bearer tok') {
        return http.Response(jsonEncode({'error': {'code': 'token_expired', 'message': 'expired'}}), 401);
      }
      return http.Response(jsonEncode({'uid': 'u1', 'displayName': 'Ana'}), 200);
    });
    final me = await api.me();
    expect(me.displayName, 'Ana');
    expect(seen, ['Bearer tok', 'Bearer tok-fresh']);
    expect(expired, isEmpty);
  });

  test('a second 401 ends the session', () async {
    final api = client((req) async =>
        http.Response(jsonEncode({'error': {'code': 'session_revoked', 'message': 'Your session was ended'}}), 401));
    await expectLater(api.me(), throwsA(isA<ApiException>().having((e) => e.isAuthError, 'isAuthError', true)));
    expect(refreshes, [false, true]);
    expect(expired, hasLength(1));
  });

  test('signed-out users are told to sign in without a network call', () async {
    var calls = 0;
    final api = client((req) async {
      calls++;
      return http.Response('{}', 200);
    }, token: null);
    await expectLater(api.me(), throwsA(isA<ApiException>()));
    expect(calls, 0);
    expect(expired, hasLength(1));
  });

  test('parses invitation previews and accept results', () async {
    final api = client((req) async {
      if (req.url.path.endsWith('/accept')) {
        return http.Response(jsonEncode({'roomId': 'r1', 'status': 'waiting'}), 200);
      }
      return http.Response(
          jsonEncode({
            'roomId': 'r1',
            'roomName': 'Family',
            'ownerName': 'Ana',
            'requireApproval': true,
            'expiresAt': '2030-01-01T00:00:00.000Z',
            'status': 'expired',
            'alreadyMember': false,
          }),
          200);
    });
    final preview = await api.previewInvite('x' * 22);
    expect(preview.roomName, 'Family');
    expect(preview.status, InviteStatus.expired);
    final (roomId, result) = await api.acceptInvite('x' * 22);
    expect(roomId, 'r1');
    expect(result, AcceptResult.waiting);
  });

  test('server errors become readable ApiExceptions', () async {
    final api = client((req) async =>
        http.Response(jsonEncode({'error': {'code': 'invite_revoked', 'message': 'This invitation was cancelled'}}), 410));
    await expectLater(
      api.acceptInvite('x' * 22),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'invite_revoked')
          .having((e) => e.message, 'message', contains('cancelled'))),
    );
  });

  test('network failures become a readable ApiException', () async {
    final api = client((req) async => throw http.ClientException('boom'));
    await expectLater(api.me(), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'network')));
  });
}
