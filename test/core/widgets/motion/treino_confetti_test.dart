import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_confetti.dart';

Widget _wrap({bool disableAnimations = false}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: SizedBox(
          width: 300,
          height: 500,
          child: TreinoConfetti(random: math.Random(1)),
        ),
      ),
    ),
  );
}

void main() {
  group('TreinoConfetti', () {
    testWidgets('monta animando y termina al completar', (tester) async {
      await tester.pumpWidget(_wrap());

      // Primer frame: el controller ya arrancó (forward() disparado en
      // didChangeDependencies) — sigue animando.
      expect(tester.hasRunningAnimations, isTrue);
      expect(
        find.descendant(
          of: find.byType(TreinoConfetti),
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
      );

      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('reduce-motion → sin animación ni CustomPaint', (tester) async {
      await tester.pumpWidget(_wrap(disableAnimations: true));

      expect(tester.hasRunningAnimations, isFalse);
      expect(
        find.descendant(
          of: find.byType(TreinoConfetti),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
    });

    testWidgets('reduce-motion activado en pleno vuelo detiene la ráfaga',
        (tester) async {
      final key = GlobalKey();
      Widget build(bool disableAnimations) => MaterialApp(
            theme: AppTheme.dark(),
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: disableAnimations),
              child: Scaffold(
                body: SizedBox(
                  width: 300,
                  height: 500,
                  child: TreinoConfetti(key: key, random: math.Random(1)),
                ),
              ),
            ),
          );

      await tester.pumpWidget(build(false));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpWidget(build(true));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('rebuild NO reinicia la ráfaga (one-shot)', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);

      // Un segundo pumpWidget con el mismo árbol simula el rebuild del
      // caller (mismo runtimeType/posición → mismo State, no re-anima).
      await tester.pumpWidget(_wrap());
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('desmontar durante la animación no explota', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump(const Duration(milliseconds: 300));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1500));

      expect(tester.takeException(), isNull);
    });
  });
}
