import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/home/widgets/home_cta_button.dart';

Widget _wrap(Widget w) => MaterialApp(
      theme: AppTheme.dark(),
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

    testWidgets('REQ-HOME-CTA-003: null onPressed — no crash on tap',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const HomeCTAButton(label: 'GO', onPressed: null),
      ));
      await tester.pump();
      await tester.tap(find.byType(HomeCTAButton));
      await tester.pump();
      // No exception means pass.
      final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets(
        'REQ-HOME-CTA-004: style — StadiumBorder, accent bg, Barlow Condensed w700',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const HomeCTAButton(label: 'GO', onPressed: null),
      ));
      await tester.pump();

      final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      final resolvedShape = btn.style?.shape?.resolve(<WidgetState>{});
      expect(resolvedShape, isA<StadiumBorder>());

      const palette = AppPalette.mintMagenta;
      final resolvedBg = btn.style?.backgroundColor?.resolve(<WidgetState>{});
      expect(resolvedBg, equals(palette.accent));

      // Text uses Barlow Condensed w700
      final textWidget = tester.widget<Text>(find.text('GO'));
      expect(
        textWidget.style?.fontFamily ??
            textWidget.style?.fontFamilyFallback?.first,
        contains(GoogleFonts.barlowCondensed().fontFamily!.split('_').first),
      );
      expect(textWidget.style?.fontWeight, equals(FontWeight.w700));
    });

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
