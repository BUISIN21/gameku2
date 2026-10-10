import 'package:connectcall/models/room_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts codes in any case and spacing', () {
    expect(RoomCode.parse('abcd-efgh-jkmn'), 'abcd-efgh-jkmn');
    expect(RoomCode.parse(' ABCD EFGH JKMN '), 'abcd-efgh-jkmn');
    expect(RoomCode.parse('abcdefghjkmn'), 'abcd-efgh-jkmn');
  });

  test('extracts the code from an invitation link', () {
    expect(RoomCode.parse('https://connectcall.web.app/?room=abcd-efgh-jkmn'), 'abcd-efgh-jkmn');
  });

  test('rejects wrong length and look-alike characters', () {
    expect(RoomCode.parse(''), isNull);
    expect(RoomCode.parse('abcd-efgh'), isNull);
    expect(RoomCode.parse('abcd-efgh-jkm0'), isNull);
    expect(RoomCode.parse('abcd-efgh-jkml'), isNull);
  });
}
