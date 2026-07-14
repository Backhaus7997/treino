import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/components/treino_badge_tokens.dart';
import 'package:treino/app/theme/tokens/components/treino_chip_tokens.dart';
import 'package:treino/app/theme/tokens/components/treino_dialog_tokens.dart';
import 'package:treino/app/theme/tokens/components/treino_empty_state_tokens.dart';
import 'package:treino/app/theme/tokens/components/treino_focus_tokens.dart';
import 'package:treino/app/theme/tokens/components/treino_kpi_card_tokens.dart';
import 'package:treino/app/theme/tokens/components/treino_list_row_tokens.dart';
import 'package:treino/app/theme/tokens/components/treino_section_header_tokens.dart';
import 'package:treino/app/theme/tokens/components/treino_table_tokens.dart';

/// Helper que inyecta [AppPalette] en el árbol (patrón de component_tokens_test.dart).
/// Cada test usa UN solo pumpWidget — nunca dos en el mismo testWidgets.
Widget _withTheme({required AppPalette palette, required Widget child}) {
  return MaterialApp(
    theme: ThemeData(extensions: [palette]),
    home: child,
  );
}

void main() {
  // ---------------------------------------------------------------------------
  // TreinoKpiCardTokens
  // ---------------------------------------------------------------------------
  group('TreinoKpiCardTokens — dark (mintMagenta)', () {
    testWidgets('background == bgCard dark (0xFF0F1513)', (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          value = TreinoKpiCardTokens.of(ctx).background;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: ink900 = #0F1513 (bgCard dark).
      expect(value, const Color(0xFF0F1513));
    });

    testWidgets('variationNegativeColor == danger (0xFFE53935)',
        (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          value = TreinoKpiCardTokens.of(ctx).variationNegativeColor;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: dangerRed = #E53935.
      expect(value, const Color(0xFFE53935));
    });

    testWidgets('titleColor == textMuted (dark)', (tester) async {
      late Color title;
      late Color textMuted;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          title = TreinoKpiCardTokens.of(ctx).titleColor;
          textMuted = AppPalette.of(ctx).textMuted;
          return const SizedBox.shrink();
        }),
      ));
      expect(title, textMuted);
    });
  });

  group('TreinoKpiCardTokens — light (mintMagentaLight)', () {
    testWidgets('background == bgCard light (0xFFFFFFFF)', (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagentaLight,
        child: Builder(builder: (ctx) {
          value = TreinoKpiCardTokens.of(ctx).background;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: white = #FFFFFF (bgCard light).
      expect(value, const Color(0xFFFFFFFF));
    });

    testWidgets('variationNegativeColor == danger light (0xFFD32F2F)',
        (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagentaLight,
        child: Builder(builder: (ctx) {
          value = TreinoKpiCardTokens.of(ctx).variationNegativeColor;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: dangerRedDark = #D32F2F (mayor contraste en light).
      expect(value, const Color(0xFFD32F2F));
    });
  });

  // ---------------------------------------------------------------------------
  // TreinoSectionHeaderTokens
  // ---------------------------------------------------------------------------
  group('TreinoSectionHeaderTokens — dark (mintMagenta)', () {
    testWidgets('titleColor == textPrimary dark', (tester) async {
      late Color title;
      late Color textPrimary;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          title = TreinoSectionHeaderTokens.of(ctx).titleColor;
          textPrimary = AppPalette.of(ctx).textPrimary;
          return const SizedBox.shrink();
        }),
      ));
      expect(title, textPrimary);
    });

    testWidgets('actionColor == accent dark (0xFF2CE5A2)', (tester) async {
      late Color action;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          action = TreinoSectionHeaderTokens.of(ctx).actionColor;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: mint500 = #2CE5A2.
      expect(action, const Color(0xFF2CE5A2));
    });

    testWidgets('titleColor dark == textPrimary dark (0xFFFFFFFF)',
        (tester) async {
      late Color title;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          title = TreinoSectionHeaderTokens.of(ctx).titleColor;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: bone = #FFFFFF (textPrimary dark).
      expect(title, const Color(0xFFFFFFFF));
    });
  });

  group('TreinoSectionHeaderTokens — light (mintMagentaLight)', () {
    testWidgets('titleColor light == textPrimary light (0xFF0F1513)',
        (tester) async {
      late Color title;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagentaLight,
        child: Builder(builder: (ctx) {
          title = TreinoSectionHeaderTokens.of(ctx).titleColor;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: inkText900 = #0F1513 (textPrimary light).
      expect(title, const Color(0xFF0F1513));
    });
  });

  // ---------------------------------------------------------------------------
  // TreinoListRowTokens
  // ---------------------------------------------------------------------------
  group('TreinoListRowTokens — dark (mintMagenta)', () {
    testWidgets('background == bg dark (0xFF0A0A0A)', (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          value = TreinoListRowTokens.of(ctx).background;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: ink950 = #0A0A0A (bg dark).
      expect(value, const Color(0xFF0A0A0A));
    });

    testWidgets('hoverBackground dark == bgCard dark (0xFF0F1513)',
        (tester) async {
      late Color hover;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          hover = TreinoListRowTokens.of(ctx).hoverBackground;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: ink900 = #0F1513 (bgCard dark).
      expect(hover, const Color(0xFF0F1513));
    });

    testWidgets('hoverBackground != background (estados distintos)',
        (tester) async {
      late Color hover;
      late Color bg;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          final t = TreinoListRowTokens.of(ctx);
          hover = t.hoverBackground;
          bg = t.background;
          return const SizedBox.shrink();
        }),
      ));
      expect(hover, isNot(equals(bg)));
    });
  });

  group('TreinoListRowTokens — light (mintMagentaLight)', () {
    testWidgets('background light == bg light (0xFFFAFAFA)', (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagentaLight,
        child: Builder(builder: (ctx) {
          value = TreinoListRowTokens.of(ctx).background;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: paper50 = #FAFAFA (bg light).
      expect(value, const Color(0xFFFAFAFA));
    });
  });

  // ---------------------------------------------------------------------------
  // TreinoChipTokens
  // ---------------------------------------------------------------------------
  group('TreinoChipTokens — dark (mintMagenta)', () {
    testWidgets('selectedForeground == accent (0xFF2CE5A2)', (tester) async {
      late Color selected;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          selected = TreinoChipTokens.of(ctx).selectedForeground;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: mint500 = #2CE5A2.
      expect(selected, const Color(0xFF2CE5A2));
    });

    testWidgets('defaultBackground dark == bgCard dark (0xFF0F1513)',
        (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          value = TreinoChipTokens.of(ctx).defaultBackground;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: ink900 = #0F1513.
      expect(value, const Color(0xFF0F1513));
    });
  });

  group('TreinoChipTokens — light (mintMagentaLight)', () {
    testWidgets('defaultBackground light == bgCard light (0xFFFFFFFF)',
        (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagentaLight,
        child: Builder(builder: (ctx) {
          value = TreinoChipTokens.of(ctx).defaultBackground;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: white = #FFFFFF.
      expect(value, const Color(0xFFFFFFFF));
    });
  });

  // ---------------------------------------------------------------------------
  // TreinoEmptyStateTokens
  // ---------------------------------------------------------------------------
  group('TreinoEmptyStateTokens — dark (mintMagenta)', () {
    testWidgets('iconColor dark == textMuted dark', (tester) async {
      late Color icon;
      late Color textMuted;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          icon = TreinoEmptyStateTokens.of(ctx).iconColor;
          textMuted = AppPalette.of(ctx).textMuted;
          return const SizedBox.shrink();
        }),
      ));
      expect(icon, textMuted);
    });

    test('iconSize == 48.0', () {
      expect(TreinoEmptyStateTokens.iconSize, 48.0);
    });

    testWidgets('iconColor dark == textMuted (0x8CFFFFFF)', (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          value = TreinoEmptyStateTokens.of(ctx).iconColor;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: white55 = 0x8CFFFFFF (textMuted dark).
      expect(value, const Color(0x8CFFFFFF));
    });
  });

  group('TreinoEmptyStateTokens — light (mintMagentaLight)', () {
    testWidgets('iconColor light == textMuted light (0x99000000)',
        (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagentaLight,
        child: Builder(builder: (ctx) {
          value = TreinoEmptyStateTokens.of(ctx).iconColor;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: black60 = 0x99000000 (textMuted light).
      expect(value, const Color(0x99000000));
    });
  });

  // ---------------------------------------------------------------------------
  // TreinoTableTokens
  // ---------------------------------------------------------------------------
  group('TreinoTableTokens — dark (mintMagenta)', () {
    testWidgets('headerBackground dark == bgCard dark (0xFF0F1513)',
        (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          value = TreinoTableTokens.of(ctx).headerBackground;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: ink900 = #0F1513.
      expect(value, const Color(0xFF0F1513));
    });

    testWidgets('rowHoverBackground dark != rowBackground dark',
        (tester) async {
      late Color hover;
      late Color bg;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          final t = TreinoTableTokens.of(ctx);
          hover = t.rowHoverBackground;
          bg = t.rowBackground;
          return const SizedBox.shrink();
        }),
      ));
      expect(hover, isNot(equals(bg)));
    });

    testWidgets('sortIndicatorColor dark == accent (0xFF2CE5A2)',
        (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          value = TreinoTableTokens.of(ctx).sortIndicatorColor;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: mint500 = #2CE5A2.
      expect(value, const Color(0xFF2CE5A2));
    });
  });

  group('TreinoTableTokens — light (mintMagentaLight)', () {
    testWidgets('headerBackground light == bgCard light (0xFFFFFFFF)',
        (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagentaLight,
        child: Builder(builder: (ctx) {
          value = TreinoTableTokens.of(ctx).headerBackground;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: white = #FFFFFF.
      expect(value, const Color(0xFFFFFFFF));
    });
  });

  // ---------------------------------------------------------------------------
  // TreinoDialogTokens
  // ---------------------------------------------------------------------------
  group('TreinoDialogTokens — dark (mintMagenta)', () {
    testWidgets('background dark == bgCard dark (0xFF0F1513)', (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          value = TreinoDialogTokens.of(ctx).background;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: ink900 = #0F1513.
      expect(value, const Color(0xFF0F1513));
    });

    testWidgets('destructiveColor dark == danger (0xFFE53935)', (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          value = TreinoDialogTokens.of(ctx).destructiveColor;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: dangerRed = #E53935.
      expect(value, const Color(0xFFE53935));
    });
  });

  group('TreinoDialogTokens — light (mintMagentaLight)', () {
    testWidgets('background light == bgCard light (0xFFFFFFFF)',
        (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagentaLight,
        child: Builder(builder: (ctx) {
          value = TreinoDialogTokens.of(ctx).background;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: white = #FFFFFF.
      expect(value, const Color(0xFFFFFFFF));
    });

    testWidgets('destructiveColor light == danger light (0xFFD32F2F)',
        (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagentaLight,
        child: Builder(builder: (ctx) {
          value = TreinoDialogTokens.of(ctx).destructiveColor;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: dangerRedDark = #D32F2F.
      expect(value, const Color(0xFFD32F2F));
    });
  });

  // ---------------------------------------------------------------------------
  // TreinoBadgeTokens
  // ---------------------------------------------------------------------------
  group('TreinoBadgeTokens — dark (mintMagenta)', () {
    testWidgets('background dark == highlight (0xFFC123E0)', (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          value = TreinoBadgeTokens.of(ctx).background;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: magenta500 = #C123E0 (highlight).
      expect(value, const Color(0xFFC123E0));
    });

    test('borderRadius == AppRadius.full (9999.0)', () {
      expect(TreinoBadgeTokens.borderRadius, 9999.0);
    });

    test('size == 16.0', () {
      expect(TreinoBadgeTokens.size, 16.0);
    });
  });

  group('TreinoBadgeTokens — light (mintMagentaLight)', () {
    testWidgets('background light == highlight (mismo en dark y light)',
        (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagentaLight,
        child: Builder(builder: (ctx) {
          value = TreinoBadgeTokens.of(ctx).background;
          return const SizedBox.shrink();
        }),
      ));
      // highlight es el mismo en dark y light (magenta de marca).
      expect(value, const Color(0xFFC123E0));
    });
  });

  // ---------------------------------------------------------------------------
  // TreinoFocusTokens
  // ---------------------------------------------------------------------------
  group('TreinoFocusTokens — anillo de foco', () {
    testWidgets('ring dark == accent (0xFF2CE5A2)', (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagenta,
        child: Builder(builder: (ctx) {
          value = TreinoFocusTokens.of(ctx).ring;
          return const SizedBox.shrink();
        }),
      ));
      // Valor pinado: mint500 = #2CE5A2 (accent).
      expect(value, const Color(0xFF2CE5A2));
    });

    testWidgets('ring light == accent (igual en ambos temas)', (tester) async {
      late Color value;
      await tester.pumpWidget(_withTheme(
        palette: AppPalette.mintMagentaLight,
        child: Builder(builder: (ctx) {
          value = TreinoFocusTokens.of(ctx).ring;
          return const SizedBox.shrink();
        }),
      ));
      // El anillo de foco siempre es el acento (marca).
      expect(value, const Color(0xFF2CE5A2));
    });

    test('ringWidth == 2.0', () {
      expect(TreinoFocusTokens.ringWidth, 2.0);
    });
  });
}
