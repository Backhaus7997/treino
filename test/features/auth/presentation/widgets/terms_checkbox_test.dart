import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/presentation/widgets/terms_checkbox.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(20), child: child)),
    );

void main() {
  group('TermsCheckbox', () {
    testWidgets('renders checkbox and terms text spans', (tester) async {
      await tester.pumpWidget(_wrap(
        TermsCheckbox(value: false, onChanged: (_) {}),
      ));
      await tester.pump();

      expect(find.byType(Checkbox), findsOneWidget);
      expect(find.textContaining('Acepto los'), findsOneWidget);
      expect(find.textContaining('Términos'), findsOneWidget);
      expect(find.textContaining('Política de Privacidad'), findsOneWidget);
    });

    testWidgets('toggling checkbox fires onChanged', (tester) async {
      bool? changed;
      await tester.pumpWidget(_wrap(
        TermsCheckbox(value: false, onChanged: (v) => changed = v),
      ));
      await tester.pump();

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(changed, isTrue);
    });

    testWidgets('tapping Términos shows Próximamente SnackBar', (tester) async {
      await tester.pumpWidget(_wrap(
        TermsCheckbox(value: false, onChanged: (_) {}),
      ));
      await tester.pump();

      // Tap on the word "Términos" inside the rich text
      await tester.tap(find.textContaining('Términos'));
      await tester.pump();

      expect(find.text('Próximamente'), findsOneWidget);
    });

    testWidgets('tapping Política de Privacidad shows Próximamente SnackBar',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TermsCheckbox(value: false, onChanged: (_) {}),
      ));
      await tester.pump();

      await tester.tap(find.textContaining('Política de Privacidad'));
      await tester.pump();

      expect(find.text('Próximamente'), findsOneWidget);
    });
  });
}
