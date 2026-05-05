import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/presentation/widgets/welcome_glitch_logo.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('WelcomeGlitchLogo', () {
    testWidgets('renders TREIN and O as rich text spans', (tester) async {
      await tester.pumpWidget(_wrap(const WelcomeGlitchLogo()));
      await tester.pump();

      final richTexts = tester.allWidgets.whereType<RichText>().toList();
      expect(richTexts, isNotEmpty);

      final combined = richTexts.map((rt) => rt.text.toPlainText()).join();
      expect(combined, contains('TREIN'));
      expect(combined, contains('O'));
    });

    testWidgets('O span is in accent color', (tester) async {
      await tester.pumpWidget(_wrap(const WelcomeGlitchLogo()));
      await tester.pump();

      const palette = AppPalette.mintMagenta;
      bool foundAccentO = false;
      for (final rt in tester.allWidgets.whereType<RichText>()) {
        final span = rt.text;
        if (span is TextSpan && span.children != null) {
          for (final child in span.children!) {
            if (child is TextSpan &&
                child.style?.color == palette.accent &&
                child.text == 'O') {
              foundAccentO = true;
            }
          }
        }
      }
      expect(foundAccentO, isTrue, reason: 'O must be in accent color');
    });

    testWidgets('strike line Container is present in the Stack',
        (tester) async {
      await tester.pumpWidget(_wrap(const WelcomeGlitchLogo()));
      await tester.pump();

      // The strike is a Positioned Container inside a Stack
      expect(find.byType(Stack), findsWidgets);
      expect(find.byType(Positioned), findsWidgets);
    });

    testWidgets('accent dash Container is present above the logo',
        (tester) async {
      await tester.pumpWidget(_wrap(const WelcomeGlitchLogo()));
      await tester.pump();

      // We have at least two Containers: the accent dash and the strike
      final containers = tester.allWidgets.whereType<Container>().toList();
      expect(containers.length, greaterThanOrEqualTo(2));
    });
  });
}
