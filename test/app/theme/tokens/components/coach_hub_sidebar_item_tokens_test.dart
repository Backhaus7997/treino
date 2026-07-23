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
    testWidgets('activeBackground == bgCard dark (0xFF0F1513)', (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          value = CoachHubSidebarItemTokens.of(ctx).activeBackground;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: ink900 = #0F1513 (bgCard dark).
      expect(value, const Color(0xFF0F1513));
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

    testWidgets('hoverBackground == accent con alpha 8% (hoverBackground)',
        (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          value = CoachHubSidebarItemTokens.of(ctx).hoverBackground;
          return const SizedBox.shrink();
        }),
      ));
      // Valor esperado: mint500 con alpha=0.08 vía withValues (precisión float).
      // Se verifica que los canales RGB son los del acento y el alpha ≈ 8%.
      final expected = AppPalette.mintMagenta.accent.withValues(alpha: 0.08);
      expect(value, expected);
      // Alpha entre 7% y 9% (tolerancia por representaciones internas).
      expect(value.a, closeTo(0.08, 0.01));
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
    testWidgets('activeBackground == bgCard light (0xFFFFFFFF)',
        (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagentaLight,
        child: Builder(builder: (ctx) {
          value = CoachHubSidebarItemTokens.of(ctx).activeBackground;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: white = #FFFFFF (bgCard light).
      expect(value, const Color(0xFFFFFFFF));
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
}
