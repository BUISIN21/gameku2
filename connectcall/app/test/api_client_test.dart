import 'dart:convert';

import 'package:connectcall/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('createRoom sends name and access key, returns the code', () async {
    late http.Request sent;
    final api = ApiClient('https://api.test', httpClient: MockClient((req) async {
      sent = req;
      return http.Response(jsonEncode({'roomCode': 'abcd-efgh-jkmn', 'expiresAt': 'x'}), 201);
    }));
    final code = await api.createRoom(displayName: 'Ana', accessKey: 'k');
    expect(code, 'abcd-efgh-jkmn');
    expect(sent.url.toString(), 'https://api.test/api/rooms');
    expect(sent.headers['X-Access-Key'], 'k');
    expect(jsonDecode(sent.body), {'displayName': 'Ana'});
  });

  test('joinRoom parses the join info', () async {
    final api = ApiClient('https://api.test', httpClient: MockClient((req) async {
      expect(req.url.path, '/api/rooms/abcd-efgh-jkmn/join');
      return http.Response(
          jsonEncode({'serverUrl': 'wss://lk', 'token': 't', 'roomCode': 'abcd-efgh-jkmn', 'identity': 'guest-1'}),
          200);
    }));
    final info = await api.joinRoom(roomCode: 'abcd-efgh-jkmn', displayName: 'Ana');
    expect(info.serverUrl, 'wss://lk');
    expect(info.token, 't');
  });

  test('maps server errors to friendly messages', () async {
    final api = ApiClient('https://api.test', httpClient: MockClient((req) async {
      return http.Response(jsonEncode({'error': {'code': 'room_not_found', 'message': 'Room not found or expired'}}), 404);
    }));
    expect(
      () => api.joinRoom(roomCode: 'abcd-efgh-jkmn', displayName: 'Ana'),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'room_not_found')
          .having((e) => e.message, 'message', contains('expired'))),
    );
  });

  test('network failures become a readable ApiException', () async {
    final api = ApiClient('https://api.test', httpClient: MockClient((req) async => throw http.ClientException('boom')));
    expect(
      () => api.createRoom(displayName: 'Ana'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'network')),
    );
  });
}
