import 'package:connectcall/models/invite_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = 'AbCdEfGhIjKlMnOpQrSt_-';

  test('accepts a full invitation link', () {
    expect(InviteLink.parse('https://connectcall.web.app/?invite=$id'), id);
    expect(InviteLink.parse('  https://x.example/app/?foo=1&invite=$id  '), id);
  });

  test('accepts a bare invitation id', () {
    expect(InviteLink.parse(id), id);
  });

  test('rejects anything else', () {
    expect(InviteLink.parse(''), isNull);
    expect(InviteLink.parse('https://connectcall.web.app/'), isNull);
    expect(InviteLink.parse('short'), isNull);
    expect(InviteLink.parse('$id!'), isNull);
  });
}
