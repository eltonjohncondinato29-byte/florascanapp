// Widget tests for FloraScan app.
//
// Uses WidgetTester to verify key UI elements are present on the auth screen
// and that the app starts correctly.

import 'package:flutter_test/flutter_test.dart';

import 'package:florascanapp/main.dart';

void main() {
  testWidgets('Auth page shows LOGIN title and toggle link', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FloraScanApp());

    // The app should show the login page by default (no session).
    expect(find.text('LOGIN'), findsOneWidget);

    // Toggle link to signup
    expect(find.textContaining('Signup'), findsOneWidget);
  });

  testWidgets('Auth page switches to SIGNUP mode', (WidgetTester tester) async {
    await tester.pumpWidget(const FloraScanApp());

    // Tap the signup link
    await tester.tap(find.text('Signup'));
    await tester.pump();

    expect(find.text('SIGNUP'), findsOneWidget);
    expect(find.text('Sign up'), findsOneWidget);
  });

  testWidgets('Auth page shows FLORA SCAN brand text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FloraScanApp());
    expect(find.text('FLORA SCAN'), findsOneWidget);
  });
}
