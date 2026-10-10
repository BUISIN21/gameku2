import 'package:connectcall/main.dart';
import 'package:connectcall/services/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('home screen validates name and meeting code', (tester) async {
    final settings = await SettingsStore.load();
    await tester.pumpWidget(ConnectCallApp(settings: settings));

    expect(find.text('ConnectCall'), findsOneWidget);
    await tester.tap(find.byKey(const Key('joinMeeting')));
    await tester.pump();
    expect(find.text('Enter your name'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'Ana');
    await tester.enterText(find.byKey(const Key('roomCode')), 'not-a-code');
    await tester.tap(find.byKey(const Key('joinMeeting')));
    await tester.pump();
    expect(find.textContaining('Enter a meeting code'), findsOneWidget);
  });

  testWidgets('invitation link pre-fills the meeting code', (tester) async {
    final settings = await SettingsStore.load();
    await tester.pumpWidget(ConnectCallApp(settings: settings, invitedRoom: 'wxyz-2345-6789'));
    expect(find.text('wxyz-2345-6789'), findsOneWidget);
  });
}
