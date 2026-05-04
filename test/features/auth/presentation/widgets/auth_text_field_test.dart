import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/auth/presentation/widgets/auth_text_field.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('AuthTextField', () {
    testWidgets('renders label text', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(
        _wrap(AuthTextField(controller: ctrl, label: 'Email')),
      );
      expect(find.text('Email'), findsOneWidget);
    });

    testWidgets('isPassword:false does not show visibility toggle',
        (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(
        _wrap(AuthTextField(controller: ctrl, label: 'Email')),
      );
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('isPassword:true starts obscured', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(
        _wrap(
          AuthTextField(
              controller: ctrl, label: 'Contraseña', isPassword: true),
        ),
      );

      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.obscureText, isTrue);
    });

    testWidgets('tap visibility toggle flips obscureText', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(
        _wrap(
          AuthTextField(
              controller: ctrl, label: 'Contraseña', isPassword: true),
        ),
      );

      // Initially obscured
      expect(
          tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);

      // Tap the toggle
      await tester.tap(find.byType(IconButton));
      await tester.pump();

      expect(tester.widget<TextField>(find.byType(TextField)).obscureText,
          isFalse);
    });

    testWidgets('Tooltip present on visibility toggle (NFR-AUTH-002)',
        (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(
        _wrap(
          AuthTextField(
              controller: ctrl, label: 'Contraseña', isPassword: true),
        ),
      );
      expect(find.byType(Tooltip), findsOneWidget);
    });
  });
}
