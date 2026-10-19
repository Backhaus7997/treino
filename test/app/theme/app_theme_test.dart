import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

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

  group('popupMenuTheme (#1558)', () {
    for (final entry in {
      'dark': (AppTheme.dark(), AppPalette.mintMagenta),
      'light': (AppTheme.light(), AppPalette.mintMagentaLight),
    }.entries) {
      testWidgets('usa tokens del kit en ${entry.key}', (tester) async {
        final (theme, palette) = entry.value;
        final p = theme.popupMenuTheme;
        expect(p.color, palette.bgCard);
        expect(p.surfaceTintColor, Colors.transparent);
        expect(p.elevation, greaterThan(0));
        final shape = p.shape! as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(AppRadius.md));
        expect(shape.side.color, palette.border);
        expect(p.textStyle!.fontFamily, contains('Barlow'));
        expect(p.textStyle!.fontWeight, FontWeight.w600);
        expect(p.textStyle!.color, palette.textPrimary);
      });

      // Con `useMaterial3: true`, `PopupMenuItem` NO lee `textStyle`: sólo
      // `labelTextStyle`. Este test mide lo que el ítem renderiza de verdad.
      testWidgets('el ítem renderiza Barlow 600 en ${entry.key}',
          (tester) async {
        final (theme, palette) = entry.value;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: PopupMenuButton<int>(
                itemBuilder: (_) => const [
                  PopupMenuItem<int>(value: 1, child: Text('EDITAR')),
                  PopupMenuItem<int>(
                    value: 2,
                    enabled: false,
                    child: Text('BLOQUEADO'),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.tap(find.byType(PopupMenuButton<int>));
        await tester.pumpAndSettle();

        final activo =
            DefaultTextStyle.of(tester.element(find.text('EDITAR'))).style;
        expect(activo.fontFamily, contains('Barlow'));
        expect(activo.fontWeight, FontWeight.w600);
        expect(activo.fontSize, AppTextSize.body);
        expect(activo.color, palette.textPrimary);

        final inactivo =
            DefaultTextStyle.of(tester.element(find.text('BLOQUEADO'))).style;
        expect(inactivo.fontWeight, FontWeight.w600);
        expect(
          inactivo.color,
          palette.textPrimary.withValues(alpha: 0.38),
        );
      });
    }

    test('labelTextStyle tiene igualdad de valor (no rebuildea la app)', () {
      expect(
        AppTheme.dark().popupMenuTheme.labelTextStyle,
        AppTheme.dark().popupMenuTheme.labelTextStyle,
      );
    });
  });

  // #1559: Material 3 tiñe el AppBar cuando hay contenido scrolleado debajo
  // (scrolled-under). Sobre las pantallas con AppBar transparente eso dibuja
  // una banda verdosa que corta lo que pasa por debajo (el avatar del perfil
  // del entrenador).
  group('appBarTheme sin tinte de scrolled-under (#1559)', () {
    for (final (nombre, tema) in [
      ('dark', AppTheme.dark()),
      ('light', AppTheme.light()),
    ]) {
      test(nombre, () {
        expect(tema.appBarTheme.scrolledUnderElevation, 0);
        expect(tema.appBarTheme.surfaceTintColor, Colors.transparent);
      });
    }
  });
}
