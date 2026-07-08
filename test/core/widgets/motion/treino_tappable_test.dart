import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_tappable.dart';

Widget _wrap({required Widget child, bool disableAnimations = false}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

/// El AnimatedScale interno, scopeado al TreinoTappable (el MaterialApp no
/// mete AnimatedScale propios, pero el scope hace el test a prueba de eso).
AnimatedScale _scaleOf(WidgetTester tester) => tester.widget<AnimatedScale>(
      find.descendant(
        of: find.byType(TreinoTappable),
        matching: find.byType(AnimatedScale),
      ),
    );

void main() {
  group('TreinoTappable', () {
    testWidgets('tap ejecuta onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(
        child: TreinoTappable(
          onTap: () => taps++,
          child: const SizedBox(width: 120, height: 48),
        ),
      ));

      await tester.tap(find.byType(TreinoTappable));
      await tester.pumpAndSettle();

      expect(taps, 1);
    });

    testWidgets('scale baja a 0.97 en press y vuelve a 1.0 al soltar',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: TreinoTappable(
          onTap: () {},
          child: const SizedBox(width: 120, height: 48),
        ),
      ));

      expect(_scaleOf(tester).scale, 1.0);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(TreinoTappable)),
      );
      // kPressTimeout garantiza que el tap-down ya se despachó incluso si el
      // arena tardara en resolverse.
      await tester.pump(kPressTimeout);
      expect(_scaleOf(tester).scale, TreinoTappable.pressedScale);

      await gesture.up();
      await tester.pump();
      expect(_scaleOf(tester).scale, 1.0);

      await tester.pumpAndSettle();
    });

    testWidgets('tap-cancel (drag fuera) también vuelve a 1.0', (tester) async {
      await tester.pumpWidget(_wrap(
        child: TreinoTappable(
          onTap: () {},
          child: const SizedBox(width: 120, height: 48),
        ),
      ));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(TreinoTappable)),
      );
      await tester.pump(kPressTimeout);
      expect(_scaleOf(tester).scale, TreinoTappable.pressedScale);

      // Arrastrar lejos cancela el tap → onTapCancel → scale de vuelta.
      await gesture.moveBy(const Offset(0, 200));
      await gesture.up();
      await tester.pump();
      expect(_scaleOf(tester).scale, 1.0);

      await tester.pumpAndSettle();
    });

    testWidgets('onTap null → sin gesture ni scale: child pelado',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const TreinoTappable(
          onTap: null,
          child: SizedBox(width: 120, height: 48),
        ),
      ));

      expect(
        find.descendant(
          of: find.byType(TreinoTappable),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(TreinoTappable),
          matching: find.byType(AnimatedScale),
        ),
        findsNothing,
      );
      // Tocar no explota (no hay handler).
      await tester.tap(find.byType(TreinoTappable), warnIfMissed: false);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'reduce-motion → el tap funciona pero sin AnimatedScale ni '
        'animación pendiente', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(
        disableAnimations: true,
        child: TreinoTappable(
          onTap: () => taps++,
          child: const SizedBox(width: 120, height: 48),
        ),
      ));

      expect(
        find.descendant(
          of: find.byType(TreinoTappable),
          matching: find.byType(AnimatedScale),
        ),
        findsNothing,
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(TreinoTappable)),
      );
      await tester.pump(kPressTimeout);
      // Presionado: sigue sin haber scale ni animación en vuelo.
      expect(
        find.descendant(
          of: find.byType(TreinoTappable),
          matching: find.byType(AnimatedScale),
        ),
        findsNothing,
      );
      expect(tester.hasRunningAnimations, isFalse);

      await gesture.up();
      await tester.pump();
      expect(taps, 1);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('onLongPress se dispara cuando se mantiene presionado',
        (tester) async {
      var longPresses = 0;
      await tester.pumpWidget(_wrap(
        child: TreinoTappable(
          onTap: () {},
          onLongPress: () => longPresses++,
          child: const SizedBox(width: 120, height: 48),
        ),
      ));

      await tester.longPress(find.byType(TreinoTappable));
      await tester.pumpAndSettle();
      expect(longPresses, 1);
    });
  });
}
