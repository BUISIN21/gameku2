import 'package:connectcall/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('validates sign-in and registration fields', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter a valid e-mail address'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);

    await tester.tap(find.text('New here? Create an account'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextFormField, 'E-mail'), 'ana@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pump();
    expect(find.text('Enter your name'), findsOneWidget);
    expect(find.text('Use at least 8 characters'), findsOneWidget);
  });

  test('display name rules match the server', () {
    expect(validateDisplayName('Ana Lima'), isNull);
    expect(validateDisplayName('José-María'), isNull);
    expect(validateDisplayName(''), isNotNull);
    expect(validateDisplayName('x' * 41), isNotNull);
    expect(validateDisplayName('<script>'), isNotNull);
  });

  testWidgets('mentions the invitation when one is pending', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen(hasInvite: true)));
    expect(find.textContaining('accept your invitation'), findsOneWidget);
  });
}
