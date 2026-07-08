import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';

Widget _wrap({required Widget child, bool disableAnimations = false}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  group('TreinoStateSwitcher', () {
    testWidgets('renderiza el child actual', (tester) async {
      await tester.pumpWidget(_wrap(
        child: const TreinoStateSwitcher(
          childKey: ValueKey('loading'),
          child: Text('cargando'),
        ),
      ));

      expect(find.text('cargando'), findsOneWidget);
    });

    testWidgets(
        'cambio de estado con keys distintas → cross-fade (ambos children '
        'coexisten a mitad de transición)', (tester) async {
      await tester.pumpWidget(_wrap(
        child: const TreinoStateSwitcher(
          childKey: ValueKey('loading'),
          child: Text('cargando'),
        ),
      ));

      await tester.pumpWidget(_wrap(
        child: const TreinoStateSwitcher(
          childKey: ValueKey('data'),
          child: Text('datos'),
        ),
      ));
      // Mitad de AppMotion.base (240ms) → el saliente todavía se desvanece
      // mientras el entrante aparece: dos FadeTransition en pantalla.
      await tester.pump(AppMotion.base * 0.5);

      expect(find.text('cargando'), findsOneWidget);
      expect(find.text('datos'), findsOneWidget);
      // Scoped al switcher: MaterialApp mete FadeTransitions propios (ruta).
      expect(
        find.descendant(
          of: find.byType(TreinoStateSwitcher),
          matching: find.byType(FadeTransition),
        ),
        findsNWidgets(2),
      );

      // Al completar la transición queda solo el entrante.
      await tester.pumpAndSettle();
      expect(find.text('cargando'), findsNothing);
      expect(find.text('datos'), findsOneWidget);
    });

    testWidgets('misma key → NO anima (documentado en el contrato de API)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const TreinoStateSwitcher(
          childKey: ValueKey('data'),
          child: Text('antes'),
        ),
      ));
      await tester.pumpWidget(_wrap(
        child: const TreinoStateSwitcher(
          childKey: ValueKey('data'),
          child: Text('después'),
        ),
      ));
      await tester.pump(AppMotion.base * 0.5);

      // Sin cross-fade: el child viejo no coexiste con el nuevo.
      expect(find.text('antes'), findsNothing);
      expect(find.text('después'), findsOneWidget);
    });

    testWidgets(
        'reduce-motion (disableAnimations: true) → el cambio es instantáneo',
        (tester) async {
      await tester.pumpWidget(_wrap(
        disableAnimations: true,
        child: const TreinoStateSwitcher(
          childKey: ValueKey('loading'),
          child: Text('cargando'),
        ),
      ));

      await tester.pumpWidget(_wrap(
        disableAnimations: true,
        child: const TreinoStateSwitcher(
          childKey: ValueKey('data'),
          child: Text('datos'),
        ),
      ));
      // AppMotion.resolve → Duration.zero: un frame extra alcanza para que
      // el AnimatedSwitcher retire el child saliente — nunca hay cross-fade.
      await tester.pump();

      expect(find.text('cargando'), findsNothing);
      expect(find.text('datos'), findsOneWidget);
    });
  });
}
