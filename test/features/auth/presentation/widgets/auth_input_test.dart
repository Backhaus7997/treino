import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/auth/presentation/widgets/auth_input.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(20), child: child)),
    );

void main() {
  group('AuthInput', () {
    testWidgets('renders with label and leading icon', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(_wrap(
        AuthInput(
          controller: ctrl,
          label: 'EMAIL',
          hint: 'tu@email.com',
          leadingIcon: TreinoIcon.mail,
        ),
      ));
      await tester.pump();

      expect(find.text('EMAIL'), findsWidgets);
      expect(find.byIcon(TreinoIcon.mail), findsOneWidget);
    });

    testWidgets('renders without label when label is null', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(_wrap(
        AuthInput(
          controller: ctrl,
          hint: 'tu@email.com',
          leadingIcon: TreinoIcon.mail,
        ),
      ));
      await tester.pump();

      // No label text rendered
      expect(find.text('EMAIL'), findsNothing);
      // But the field and icon are still present
      expect(find.byIcon(TreinoIcon.mail), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('renders suffix eye toggle when suffixToggle is true',
        (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(_wrap(
        AuthInput(
          controller: ctrl,
          label: 'CONTRASEÑA',
          leadingIcon: TreinoIcon.lock,
          obscureText: true,
          suffixToggle: true,
        ),
      ));
      await tester.pump();

      // Initially obscured — eye icon should be visible
      expect(find.byIcon(TreinoIcon.eye), findsOneWidget);
    });

    testWidgets('tapping eye toggle flips obscureText', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(_wrap(
        AuthInput(
          controller: ctrl,
          label: 'CONTRASEÑA',
          leadingIcon: TreinoIcon.lock,
          obscureText: true,
          suffixToggle: true,
        ),
      ));
      await tester.pump();

      // Eye icon visible (obscured)
      expect(find.byIcon(TreinoIcon.eye), findsOneWidget);
      expect(find.byIcon(TreinoIcon.eyeOff), findsNothing);

      // Tap the toggle
      await tester.tap(find.byIcon(TreinoIcon.eye));
      await tester.pump();

      // Now eyeOff should be visible (revealed)
      expect(find.byIcon(TreinoIcon.eyeOff), findsOneWidget);
      expect(find.byIcon(TreinoIcon.eye), findsNothing);
    });

    testWidgets('no eye icon when suffixToggle is false', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(_wrap(
        AuthInput(
          controller: ctrl,
          label: 'EMAIL',
          leadingIcon: TreinoIcon.mail,
        ),
      ));
      await tester.pump();

      expect(find.byIcon(TreinoIcon.eye), findsNothing);
      expect(find.byIcon(TreinoIcon.eyeOff), findsNothing);
    });

    testWidgets('filled background uses TextFormField', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(_wrap(
        AuthInput(
          controller: ctrl,
          label: 'EMAIL',
          leadingIcon: TreinoIcon.mail,
        ),
      ));
      await tester.pump();

      expect(find.byType(TextFormField), findsOneWidget);
    });
  });
}
