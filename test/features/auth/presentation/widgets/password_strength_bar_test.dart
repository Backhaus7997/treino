import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/presentation/widgets/password_strength_bar.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(20), child: child)),
    );

void main() {
  group('PasswordStrengthBar', () {
    testWidgets('less than 8 chars → 0 lit segments', (tester) async {
      await tester
          .pumpWidget(_wrap(const PasswordStrengthBar(password: 'abc')));
      await tester.pump();
      expect(find.byType(PasswordStrengthBar), findsOneWidget);
      // Hint should not show "Fuerte."
      expect(find.text('Fuerte.'), findsNothing);
    });

    testWidgets('8+ chars letters only → 1 lit segment, Débil hint',
        (tester) async {
      await tester
          .pumpWidget(_wrap(const PasswordStrengthBar(password: 'abcdefgh')));
      await tester.pump();
      expect(find.textContaining('Débil'), findsOneWidget);
      expect(find.text('Fuerte.'), findsNothing);
    });

    testWidgets('8+ chars letter+number → 2 lit segments, Buena hint',
        (tester) async {
      await tester
          .pumpWidget(_wrap(const PasswordStrengthBar(password: 'abcdef12')));
      await tester.pump();
      expect(find.textContaining('Buena'), findsOneWidget);
      expect(find.text('Fuerte.'), findsNothing);
    });

    testWidgets('8+ chars letter+number+symbol → 3 lit segments, Fuerte hint',
        (tester) async {
      await tester
          .pumpWidget(_wrap(const PasswordStrengthBar(password: 'abcdef1!')));
      await tester.pump();
      expect(find.text('Fuerte.'), findsOneWidget);
    });
  });
}
