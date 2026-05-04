import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/presentation/widgets/treino_logo.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('TreinoLogo', () {
    testWidgets('renders the full word TREINO in a RichText', (tester) async {
      await tester.pumpWidget(_wrap(const TreinoLogo()));
      await tester.pump();

      // The full text should contain "TREIN" and "O"
      final richTexts = find.byType(RichText);
      expect(richTexts, findsWidgets);

      // Verify the combined text is "TREINO"
      final text = tester.allWidgets
          .whereType<RichText>()
          .map((rt) => rt.text.toPlainText())
          .join();
      expect(text, contains('TREIN'));
      expect(text, contains('O'));
    });

    testWidgets('renders with default size 56', (tester) async {
      await tester.pumpWidget(_wrap(const TreinoLogo()));
      await tester.pump();

      expect(find.byType(TreinoLogo), findsOneWidget);
      final logo = tester.widget<TreinoLogo>(find.byType(TreinoLogo));
      expect(logo.size, 56.0);
    });

    testWidgets('accepts custom size parameter', (tester) async {
      await tester.pumpWidget(_wrap(const TreinoLogo(size: 80)));
      await tester.pump();

      final logo = tester.widget<TreinoLogo>(find.byType(TreinoLogo));
      expect(logo.size, 80.0);
    });

    testWidgets('O is rendered in accent color', (tester) async {
      await tester.pumpWidget(_wrap(const TreinoLogo()));
      await tester.pump();

      const palette = AppPalette.mintMagenta;
      // Find a RichText and check that the last span uses accent color
      final richTexts = tester.allWidgets.whereType<RichText>().toList();
      expect(richTexts, isNotEmpty);
      // Find the one that has TextSpans with accent color
      bool foundAccent = false;
      for (final rt in richTexts) {
        final span = rt.text;
        if (span is TextSpan && span.children != null) {
          for (final child in span.children!) {
            if (child is TextSpan &&
                child.style?.color == palette.accent &&
                child.text == 'O') {
              foundAccent = true;
            }
          }
        }
      }
      expect(foundAccent, isTrue,
          reason: 'Expected the O to be rendered in accent color');
    });

    testWidgets('TREIN is rendered in textPrimary color', (tester) async {
      await tester.pumpWidget(_wrap(const TreinoLogo()));
      await tester.pump();

      const palette = AppPalette.mintMagenta;
      bool foundPrimary = false;
      final richTexts = tester.allWidgets.whereType<RichText>().toList();
      for (final rt in richTexts) {
        final span = rt.text;
        if (span is TextSpan && span.children != null) {
          for (final child in span.children!) {
            if (child is TextSpan &&
                child.style?.color == palette.textPrimary &&
                child.text == 'TREIN') {
              foundPrimary = true;
            }
          }
        }
      }
      expect(foundPrimary, isTrue,
          reason: 'Expected TREIN to be rendered in textPrimary color');
    });
  });
}
