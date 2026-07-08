import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';

Widget _wrap({required Widget child, bool disableAnimations = false}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

/// Opacity actual del fade, scopeado al TreinoFadeSlideIn (MaterialApp mete
/// FadeTransitions propios de ruta).
double _opacityOf(WidgetTester tester) {
  final fade = tester.widget<FadeTransition>(
    find
        .descendant(
          of: find.byType(TreinoFadeSlideIn),
          matching: find.byType(FadeTransition),
        )
        .first,
  );
  return fade.opacity.value;
}

/// Desplazamiento vertical actual del Transform.translate interno.
double _translationYOf(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find
        .descendant(
          of: find.byType(TreinoFadeSlideIn),
          matching: find.byType(Transform),
        )
        .first,
  );
  return transform.transform.getTranslation().y;
}

void main() {
  group('TreinoFadeSlideIn', () {
    testWidgets(
        'arranca invisible/desplazado y tras delay + duración queda '
        'visible y en posición', (tester) async {
      const delay = Duration(milliseconds: 100);
      await tester.pumpWidget(_wrap(
        child: const TreinoFadeSlideIn(delay: delay, child: Text('contenido')),
      ));

      // Primer frame: invisible y `distance` px abajo.
      expect(_opacityOf(tester), 0.0);
      expect(_translationYOf(tester), AppMotion.slideMd);

      await tester.pump(delay);
      await tester.pump(AppMotion.base);

      expect(_opacityOf(tester), 1.0);
      expect(_translationYOf(tester), 0.0);
      expect(find.text('contenido'), findsOneWidget);
    });

    testWidgets(
        'rebuild con otro child NO re-anima (one-shot: sin fase invisible)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const TreinoFadeSlideIn(child: Text('uno')),
      ));
      await tester.pumpAndSettle();
      expect(_opacityOf(tester), 1.0);

      // Riverpod re-emite → el caller reconstruye con child distinto. El
      // State (mismo runtimeType, misma posición) sobrevive → no re-anima.
      await tester.pumpWidget(_wrap(
        child: const TreinoFadeSlideIn(child: Text('dos')),
      ));

      // Primer frame post-rebuild: ya visible, sin pasar por opacity 0.
      expect(_opacityOf(tester), 1.0);
      expect(_translationYOf(tester), 0.0);
      expect(find.text('dos'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('el delay se respeta: durante la espera sigue invisible',
        (tester) async {
      const delay = Duration(milliseconds: 200);
      await tester.pumpWidget(_wrap(
        child: const TreinoFadeSlideIn(delay: delay, child: Text('x')),
      ));

      // A mitad del delay: todavía nada.
      await tester.pump(const Duration(milliseconds: 100));
      expect(_opacityOf(tester), 0.0);
      expect(_translationYOf(tester), AppMotion.slideMd);

      // Pasado el delay + media entrada: animando (parcialmente visible).
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(AppMotion.base * 0.5);
      expect(_opacityOf(tester), greaterThan(0.0));
      expect(_opacityOf(tester), lessThan(1.0));

      await tester.pumpAndSettle();
      expect(_opacityOf(tester), 1.0);
    });

    testWidgets(
        'reduce-motion → visible al primer frame, sin delay ni animación',
        (tester) async {
      await tester.pumpWidget(_wrap(
        disableAnimations: true,
        child: const TreinoFadeSlideIn(
          delay: Duration(milliseconds: 200),
          child: Text('x'),
        ),
      ));

      // Primer frame, sin avanzar el reloj: ya visible y en posición.
      expect(_opacityOf(tester), 1.0);
      expect(_translationYOf(tester), 0.0);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('desmontar durante el delay no explota (sin timers sueltos)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const TreinoFadeSlideIn(
          delay: Duration(milliseconds: 300),
          child: Text('x'),
        ),
      ));
      // En pleno delay…
      await tester.pump(const Duration(milliseconds: 100));

      // …desmonte. El delay vive en el controller (Interval), no en un
      // Future.delayed: dispose descarta el ticker y no queda nada colgado.
      await tester.pumpWidget(_wrap(child: const SizedBox()));
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
    });

    testWidgets('distance custom se respeta en el primer frame',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const TreinoFadeSlideIn(
          distance: AppMotion.slideLg,
          child: Text('x'),
        ),
      ));

      expect(_translationYOf(tester), AppMotion.slideLg);
      await tester.pumpAndSettle();
      expect(_translationYOf(tester), 0.0);
    });
  });
}
