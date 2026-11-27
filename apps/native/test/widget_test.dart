import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine_me_native/src/screens/login_screen.dart';
import 'package:mine_me_native/src/screens/register_screen.dart';

void main() {
  testWidgets('MINE-ME login screen offers account registration',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('MINE-ME'), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Créer un compte'), findsOneWidget);

    await tester.tap(find.text('Créer un compte'));
    await tester.pumpAndSettle();

    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(find.text('Rejoindre MINE-ME'), findsOneWidget);
    expect(find.text('Code d’invitation / parrainage'), findsOneWidget);
    expect(find.text('J’ai lu et j’accepte les conditions de participation.'), findsOneWidget);
  });
}
