import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';

/// Tests for [AppTheme.light()].
///
/// Uses [testWidgets] so that [GoogleFonts] has the Flutter binding available
/// (it reads from the asset bundle via PlatformAssetBundle and falls back
/// gracefully when fonts cannot be loaded in the test environment).
///
/// REQ-LM-002, SCENARIO-804, SCENARIO-805, SCENARIO-806.
void main() {
  group('AppTheme.light()', () {
    testWidgets('SCENARIO-804: brightness is Brightness.light', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              final brightness = Theme.of(context).brightness;
              expect(brightness, Brightness.light);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets(
        'SCENARIO-805: AppPalette extension resolves to mintMagentaLight',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              final palette = AppPalette.of(context);
              expect(palette, equals(AppPalette.mintMagentaLight));
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('SCENARIO-806: bgPrimary (bg) is near-white (luminance >= 0.9)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              final palette = AppPalette.of(context);
              expect(
                palette.bg.computeLuminance(),
                greaterThanOrEqualTo(0.9),
                reason: 'bgPrimary must be near-white in light palette',
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('textPrimary is near-black (luminance <= 0.1)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              final palette = AppPalette.of(context);
              // SCENARIO-801
              expect(
                palette.textPrimary.computeLuminance(),
                lessThanOrEqualTo(0.1),
                reason: 'textPrimary must be near-black in light palette',
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('AppTheme.dark() brightness is Brightness.dark',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) {
              expect(Theme.of(context).brightness, Brightness.dark);
              expect(
                AppPalette.of(context),
                equals(AppPalette.mintMagenta),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });
}
