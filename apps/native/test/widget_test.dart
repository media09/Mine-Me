import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine_me_native/src/screens/login_screen.dart';

void main() {
  testWidgets('MINE-ME login screen displays member sign-in controls',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('MINE-ME'), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.textContaining('inscriptions et le parrainage'), findsOneWidget);
  });
}
