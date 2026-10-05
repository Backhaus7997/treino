import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
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

  Widget wrapWith(ThemeData theme, Widget child) => MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(20), child: child),
        ),
      );

  /// Colores de los dos links (los TextSpan con recognizer).
  List<Color?> linkColors(WidgetTester tester) {
    final colors = <Color?>[];
    for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
      rt.text.visitChildren((span) {
        if (span is TextSpan && span.recognizer != null) {
          colors.add(span.style?.color);
        }
        return true;
      });
    }
    return colors;
  }

  group('TermsNoticeText links (SCENARIO-CHW-AUTH-030)', () {
    testWidgets('en light los links usan accentText (accent es tinta, 1,57:1)',
        (tester) async {
      await tester.pumpWidget(
        wrapWith(AppTheme.light(), const TermsNoticeText()),
      );
      await tester.pump();

      const light = AppPalette.mintMagentaLight;
      expect(light.accentText, isNot(light.accent),
          reason: 'control: si fueran iguales el test no distingue nada');
      expect(linkColors(tester), [light.accentText, light.accentText]);
    });

    testWidgets('en dark el color de los links no cambia', (tester) async {
      await tester.pumpWidget(
        wrapWith(AppTheme.dark(), const TermsNoticeText()),
      );
      await tester.pump();

      const dark = AppPalette.mintMagenta;
      expect(dark.accentText, dark.accent);
      expect(linkColors(tester), [dark.accent, dark.accent]);
    });
  });

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
