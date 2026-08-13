import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_success_check.dart';

Widget _wrap({bool disableAnimations = false, double? size}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: Center(
          child: size == null
              ? const TreinoSuccessCheck()
              : TreinoSuccessCheck(size: size),
        ),
      ),
    ),
  );
}

void main() {
  group('TreinoSuccessCheck', () {
    testWidgets('monta con el tamaño default (64x64) y pinta un CustomPaint',
        (tester) async {
      await tester.pumpWidget(_wrap());

      expect(
        tester.getSize(find.byType(TreinoSuccessCheck)),
        const Size(64, 64),
      );
      expect(
        find.descendant(
          of: find.byType(TreinoSuccessCheck),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
    });

    testWidgets('tamaño custom se respeta', (tester) async {
      await tester.pumpWidget(_wrap(size: 96));

      expect(
        tester.getSize(find.byType(TreinoSuccessCheck)),
        const Size(96, 96),
      );
    });

    testWidgets('arranca animando y termina al completar', (tester) async {
      await tester.pumpWidget(_wrap());

      // Primer frame: el controller ya arrancó (forward() disparado en
      // didChangeDependencies) — sigue animando.
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('reduce-motion → sin animación desde el primer frame',
        (tester) async {
      await tester.pumpWidget(_wrap(disableAnimations: true));

      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('rebuild NO reinicia el dibujo (one-shot)', (tester) async {
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
      await tester.pump(const Duration(milliseconds: 100));

      // En pleno dibujo, desmonte. Sin timers sueltos (controller vive en
      // el State, dispose lo libera).
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
    });
  });
}
