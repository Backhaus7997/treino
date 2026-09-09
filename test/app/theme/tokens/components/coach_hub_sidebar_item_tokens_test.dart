import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/components/coach_hub_sidebar_item_tokens.dart';
import 'package:treino/app/theme/tokens/primitives.dart';

/// Helper que inyecta [AppPalette] en el árbol (igual al patrón de component_tokens_test.dart).
Widget _withTheme({required AppPalette palette, required Widget child}) {
  return MaterialApp(
    theme: ThemeData(extensions: [palette]),
    home: child,
  );
}

void main() {
  group('CoachHubSidebarItemTokens — dark (mintMagenta)', () {
    testWidgets('activeBackground == acento al 16%', (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          value = CoachHubSidebarItemTokens.of(ctx).activeBackground;
          return const SizedBox.shrink();
        }),
      ));
      // El activo lleva el ACENTO. Antes era `bgCard`, que en claro es blanco
      // sobre un sidebar casi blanco y no se veía; ver la nota del token.
      expect(value, AppPalette.mintMagenta.accent.withValues(alpha: 0.16));
      expect(value.a, closeTo(0.16, 0.01));
    });

    testWidgets('activeForeground == accent (0xFF2CE5A2)', (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          value = CoachHubSidebarItemTokens.of(ctx).activeForeground;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: mint500 = #2CE5A2.
      expect(value, const Color(0xFF2CE5A2));
    });

    testWidgets('inactiveForeground == textPrimary dark (0xFFFFFFFF)',
        (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          value = CoachHubSidebarItemTokens.of(ctx).inactiveForeground;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: bone = #FFFFFF (textPrimary dark).
      expect(value, const Color(0xFFFFFFFF));
    });

    testWidgets('hoverBackground == lavado NEUTRO, sin acento', (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          value = CoachHubSidebarItemTokens.of(ctx).hoverBackground;
          return const SizedBox.shrink();
        }),
      ));
      expect(value, AppPalette.mintMagenta.surfaceSubtle);
      // Y es NEUTRO: mismos canales R, G y B. Éste es el candado de verdad —
      // si alguien vuelve a darle el acento al hover, el hovereado se lee como
      // seleccionado y volvemos al reporte del PF.
      expect(value.r, closeTo(value.g, 0.001));
      expect(value.g, closeTo(value.b, 0.001));
    });

    testWidgets('badgeBackground == highlight (0xFFC123E0)', (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          value = CoachHubSidebarItemTokens.of(ctx).badgeBackground;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: magenta500 = #C123E0 (highlight).
      expect(value, const Color(0xFFC123E0));
    });

    testWidgets('hoverBackground != activeBackground en dark', (tester) async {
      late Color hover;
      late Color active;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          final tokens = CoachHubSidebarItemTokens.of(ctx);
          hover = tokens.hoverBackground;
          active = tokens.activeBackground;
          return const SizedBox.shrink();
        }),
      ));
      expect(hover, isNot(equals(active)));
    });

    test('borderRadius == AppRadius.sm (12.0)', () {
      expect(CoachHubSidebarItemTokens.borderRadius, AppRadius.sm);
      expect(CoachHubSidebarItemTokens.borderRadius, 12.0);
    });

    test('paddingH == AppSpacing.s14 (14.0)', () {
      expect(CoachHubSidebarItemTokens.paddingH, AppSpacing.s14);
      expect(CoachHubSidebarItemTokens.paddingH, 14.0);
    });

    test('paddingV == AppSpacing.s12 (12.0)', () {
      expect(CoachHubSidebarItemTokens.paddingV, AppSpacing.s12);
      expect(CoachHubSidebarItemTokens.paddingV, 12.0);
    });
  });

  group('CoachHubSidebarItemTokens — light (mintMagentaLight)', () {
    testWidgets('activeBackground == acento al 16% (light)',
        (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagentaLight,
        child: Builder(builder: (ctx) {
          value = CoachHubSidebarItemTokens.of(ctx).activeBackground;
          return const SizedBox.shrink();
        }),
      ));
      expect(value, AppPalette.mintMagentaLight.accent.withValues(alpha: 0.16));
      expect(value.a, closeTo(0.16, 0.01));
    });

    testWidgets('inactiveForeground == textPrimary light (0xFF0F1513)',
        (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagentaLight,
        child: Builder(builder: (ctx) {
          value = CoachHubSidebarItemTokens.of(ctx).inactiveForeground;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: inkText900 = #0F1513 (textPrimary light).
      expect(value, const Color(0xFF0F1513));
    });

    testWidgets('hoverBackground != activeBackground en light', (tester) async {
      late Color hover;
      late Color active;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagentaLight,
        child: Builder(builder: (ctx) {
          final tokens = CoachHubSidebarItemTokens.of(ctx);
          hover = tokens.hoverBackground;
          active = tokens.activeBackground;
          return const SizedBox.shrink();
        }),
      ));
      expect(hover, isNot(equals(active)));
    });
  });

  // ── El candado que faltaba ────────────────────────────────────────────────
  //
  // El guard viejo decía `hoverBackground != activeBackground`. Pasaba, y el
  // bug existía igual: DISTINTOS no es «el activo se lee más fuerte». Con el
  // activo en blanco sobre un sidebar casi blanco y el hover en verde, los dos
  // eran distintos y el que mandaba era el equivocado.
  group('CoachHubSidebarItemTokens — el activo se LEE', () {
    for (final caso in <(String, AppPalette)>[
      ('dark', AppPalette.mintMagenta),
      ('light', AppPalette.mintMagentaLight),
    ]) {
      testWidgets('${caso.$1}: el label del item activo pasa WCAG AA',
          (tester) async {
        late CoachHubSidebarItemTokens t;
        await tester.pumpWidget(_withTheme(
          palette: caso.$2,
          child: Builder(builder: (ctx) {
            t = CoachHubSidebarItemTokens.of(ctx);
            return const SizedBox.shrink();
          }),
        ));

        // El fondo del item es TRANSLÚCIDO: se compone sobre el fondo del
        // sidebar (`palette.bg`), y el contraste hay que medirlo contra el
        // resultado, no contra el token suelto.
        final fondo = Color.alphaBlend(t.activeBackground, caso.$2.bg);
        final ratio = _ratio(t.activeForeground, fondo);

        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '${caso.$1}: el label activo mide '
              '${ratio.toStringAsFixed(2)}:1 sobre su propia píldora. Con '
              '`accent` en vez de `accentText` daba 1,64:1 en claro — el item '
              'seleccionado era ilegible.',
        );
      });

      testWidgets('${caso.$1}: hover y activo se distinguen por TONO',
          (tester) async {
        late CoachHubSidebarItemTokens t;
        await tester.pumpWidget(_withTheme(
          palette: caso.$2,
          child: Builder(builder: (ctx) {
            t = CoachHubSidebarItemTokens.of(ctx);
            return const SizedBox.shrink();
          }),
        ));

        // El hover NO tiene tono: R == G == B. El activo SÍ. Es lo que hace
        // que no se confundan, porque en luminancia son casi iguales.
        expect(t.hoverBackground.r, closeTo(t.hoverBackground.g, 0.001));
        expect(t.hoverBackground.g, closeTo(t.hoverBackground.b, 0.001));
        expect(t.activeBackground, isNot(equals(t.hoverBackground)));
      });
    }
  });
}

/// Contraste WCAG entre dos colores YA OPACOS.
double _ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
