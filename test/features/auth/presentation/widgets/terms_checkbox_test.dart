import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/presentation/legal/legal_document_screen.dart';
import 'package:treino/features/auth/presentation/widgets/terms_checkbox.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(20), child: child),
        ),
      );

  String plainText(WidgetTester tester) => tester
      .widgetList<RichText>(find.byType(RichText))
      .map((rt) => rt.text.toPlainText())
      .join(' ');

  group('TermsCheckbox', () {
    testWidgets('renders checkbox and the full terms sentence', (tester) async {
      await tester.pumpWidget(wrap(
        TermsCheckbox(value: false, onChanged: (_) {}),
      ));
      await tester.pump();

      expect(find.byType(Checkbox), findsOneWidget);
      final text = plainText(tester);
      expect(text, contains('Acepto los'));
      expect(text, contains('Términos'));
      expect(text, contains('Política de Privacidad'));
    });

    testWidgets('toggling the checkbox fires onChanged', (tester) async {
      bool? changed;
      await tester.pumpWidget(wrap(
        TermsCheckbox(value: false, onChanged: (v) => changed = v),
      ));
      await tester.pump();

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(changed, isTrue);
    });

    testWidgets('tapping Términos opens the in-app Terms screen, no SnackBar',
        (tester) async {
      await tester.pumpWidget(wrap(
        TermsCheckbox(value: false, onChanged: (_) {}),
      ));
      await tester.pump();

      await tester.tapOnText(find.textRange.ofSubstring('Términos'));
      await tester.pumpAndSettle();

      expect(find.byType(LegalDocumentScreen), findsOneWidget);
      expect(find.text('Términos y Condiciones'), findsOneWidget);
      // The old dead-end SnackBar must be gone — users can now actually read it.
      expect(find.text('Próximamente'), findsNothing);
    });

    testWidgets(
        'tapping Política de Privacidad opens the in-app Privacy screen',
        (tester) async {
      await tester.pumpWidget(wrap(
        TermsCheckbox(value: false, onChanged: (_) {}),
      ));
      await tester.pump();

      await tester
          .tapOnText(find.textRange.ofSubstring('Política de Privacidad'));
      await tester.pumpAndSettle();

      expect(find.byType(LegalDocumentScreen), findsOneWidget);
      expect(find.text('Política de Privacidad'), findsOneWidget);
    });
  });
}
