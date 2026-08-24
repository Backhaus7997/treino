import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/tokens/components/treino_button_tokens.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/home/widgets/home_cta_button.dart';

Widget _wrap(Widget w, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: Scaffold(body: Center(child: w)),
    );

void main() {
  group('HomeCTAButton', () {
    testWidgets('REQ-HOME-CTA-001: renders label text', (tester) async {
      await tester.pumpWidget(_wrap(
        const HomeCTAButton(
          label: '▶ EMPEZAR ENTRENAMIENTO',
          onPressed: null,
        ),
      ));
      await tester.pump();
      expect(find.text('▶ EMPEZAR ENTRENAMIENTO'), findsOneWidget);

      await tester.pumpWidget(_wrap(
        HomeCTAButton(label: 'OTRO LABEL', onPressed: () {}),
      ));
      await tester.pump();
      expect(find.text('OTRO LABEL'), findsOneWidget);
    });

    testWidgets('REQ-HOME-CTA-002: tap fires onPressed exactly once',
        (tester) async {
      var counter = 0;
      await tester.pumpWidget(_wrap(
        HomeCTAButton(label: 'GO', onPressed: () => counter++),
      ));
      await tester.pump();
      await tester.tap(find.byType(HomeCTAButton));
      await tester.pump();
      expect(counter, equals(1));
    });

    testWidgets(
        'REQ-HOME-CTA-003: null onPressed — no crash on tap y sin gesture '
        '(TreinoTappable devuelve el child pelado)', (tester) async {
      await tester.pumpWidget(_wrap(
        const HomeCTAButton(label: 'GO', onPressed: null),
      ));
      await tester.pump();
      await tester.tap(find.byType(HomeCTAButton), warnIfMissed: false);
      await tester.pump();
      // No exception means pass. Disabled → TreinoTappable no monta gesture.
      expect(
        find.descendant(
          of: find.byType(HomeCTAButton),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    });

    testWidgets(
        'REQ-HOME-CTA-004: style — StadiumBorder, accent bg, Barlow Condensed w700',
        (tester) async {
      await tester.pumpWidget(_wrap(
        HomeCTAButton(label: 'GO', onPressed: () {}),
      ));
      await tester.pump();

      // TREINO Motion PR3: el pill ahora es un Container con ShapeDecoration
      // (TreinoTappable + scale reemplazan al ElevatedButton + ripple).
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(HomeCTAButton),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as ShapeDecoration;
      expect(decoration.shape, isA<StadiumBorder>());

      const palette = AppPalette.mintMagenta;
      expect(decoration.color, equals(palette.accent));

      // Text uses Barlow Condensed w700
      final textWidget = tester.widget<Text>(find.text('GO'));
      expect(
        textWidget.style?.fontFamily ??
            textWidget.style?.fontFamilyFallback?.first,
        contains(GoogleFonts.barlowCondensed().fontFamily!.split('_').first),
      );
      expect(textWidget.style?.fontWeight, equals(FontWeight.w700));
    });

    // REQ-HOME-CTA-006 — AGENTS.md regla 2: todo par de tokens donde `accent`
    // es FONDO se mide en las DOS paletas. `palette.bg` sobre accent da
    // 12.10:1 en dark pero 1.57:1 en light, muy debajo de WCAG AA (4.5:1).
    // El foreground va con el ink invariante de TreinoButtonTokens.
    for (final (themeName, theme, palette) in <(String, ThemeData, AppPalette)>[
      ('dark', AppTheme.dark(), AppPalette.mintMagenta),
      ('light', AppTheme.light(), AppPalette.mintMagentaLight),
    ]) {
      testWidgets(
          'REQ-HOME-CTA-006 [$themeName]: foreground es el ink invariante, '
          'nunca palette.bg', (tester) async {
        await tester.pumpWidget(_wrap(
          HomeCTAButton(
            label: 'GO',
            onPressed: () {},
            leadingIcon: TreinoIcon.play,
          ),
          theme: theme,
        ));
        await tester.pump();

        final ctx = tester.element(find.byType(HomeCTAButton));
        final expected = TreinoButtonTokens.foreground(ctx);

        // El fondo efectivamente es accent — si no, el test no prueba nada.
        final container = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(HomeCTAButton),
                matching: find.byType(Container),
              )
              .first,
        );
        expect((container.decoration! as ShapeDecoration).color,
            equals(palette.accent));

        expect(tester.widget<Text>(find.text('GO')).style?.color,
            equals(expected));
        expect(tester.widget<Icon>(find.byIcon(TreinoIcon.play)).color,
            equals(expected));

        // Guarda contra la regresión, sólo donde los valores divergen: en
        // dark `palette.bg` ES ink950 y coincide con el token, así que la
        // aserción no distinguiría nada. En light da 1.57:1 y es el bug.
        if (themeName == 'light') {
          expect(tester.widget<Text>(find.text('GO')).style?.color,
              isNot(equals(palette.bg)),
              reason: 'palette.bg sobre accent da 1.57:1 en la paleta light — '
                  'viola WCAG AA (AGENTS.md regla 2)');
        }
      });
    }

    testWidgets('REQ-HOME-CTA-005: leadingIcon present/absent', (tester) async {
      // With leadingIcon
      await tester.pumpWidget(_wrap(
        const HomeCTAButton(
          label: 'PLAY',
          onPressed: null,
          leadingIcon: TreinoIcon.play,
        ),
      ));
      await tester.pump();
      expect(find.byIcon(TreinoIcon.play), findsOneWidget);

      // Without leadingIcon — no Icon widget
      await tester.pumpWidget(_wrap(
        const HomeCTAButton(label: 'PLAY', onPressed: null),
      ));
      await tester.pump();
      expect(find.byType(Icon), findsNothing);
    });
  });
}
