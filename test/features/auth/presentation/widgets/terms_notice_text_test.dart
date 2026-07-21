import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/presentation/legal/legal_document_screen.dart';
import 'package:treino/features/auth/presentation/widgets/terms_notice_text.dart';

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

  group('TermsNoticeText', () {
    testWidgets('renders the full consent sentence', (tester) async {
      await tester.pumpWidget(wrap(const TermsNoticeText()));
      await tester.pump();

      final text = plainText(tester);
      expect(text, contains('Al continuar con Google o Apple'));
      expect(text, contains('Términos y Condiciones'));
      expect(text, contains('Política de Privacidad'));
    });

    testWidgets('tapping Términos y Condiciones opens the in-app Terms screen',
        (tester) async {
      await tester.pumpWidget(wrap(const TermsNoticeText()));
      await tester.pump();

      await tester
          .tapOnText(find.textRange.ofSubstring('Términos y Condiciones'));
      await tester.pumpAndSettle();

      expect(find.byType(LegalDocumentScreen), findsOneWidget);
      expect(find.text('Términos y Condiciones'), findsOneWidget);
    });

    testWidgets(
        'tapping Política de Privacidad opens the in-app Privacy screen',
        (tester) async {
      await tester.pumpWidget(wrap(const TermsNoticeText()));
      await tester.pump();

      await tester
          .tapOnText(find.textRange.ofSubstring('Política de Privacidad'));
      await tester.pumpAndSettle();

      expect(find.byType(LegalDocumentScreen), findsOneWidget);
      expect(find.text('Política de Privacidad'), findsOneWidget);
    });
  });
}
