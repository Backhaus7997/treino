import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_shimmer.dart';

/// Harness mínimo: MaterialApp con el theme real (AppPalette vía extension)
/// y control explícito de `disableAnimations` (reduce-motion).
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
  group('TreinoShimmer', () {
    testWidgets('renderiza el child intacto', (tester) async {
      await tester.pumpWidget(_wrap(
        child: const TreinoShimmer(
          child: SizedBox(
            key: ValueKey('skeleton-box'),
            width: 120,
            height: 14,
          ),
        ),
      ));

      expect(find.byKey(const ValueKey('skeleton-box')), findsOneWidget);
    });

    testWidgets('anima: con animaciones habilitadas monta el ShaderMask',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const TreinoShimmer(child: SizedBox(width: 120, height: 14)),
      ));

      expect(find.byType(ShaderMask), findsOneWidget);
      // El loop está corriendo: hay frames agendados por el controller.
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets(
        'reduce-motion (disableAnimations: true) → child estático, '
        'sin ShaderMask ni animación corriendo', (tester) async {
      await tester.pumpWidget(_wrap(
        disableAnimations: true,
        child: const TreinoShimmer(
          child: SizedBox(
            key: ValueKey('skeleton-box'),
            width: 120,
            height: 14,
          ),
        ),
      ));

      // El child se devuelve tal cual — el barrido no existe en el árbol.
      expect(find.byKey(const ValueKey('skeleton-box')), findsOneWidget);
      expect(find.byType(ShaderMask), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets(
        'enabled: false (skeleton en estado de error/null) → child estático, '
        'sin ShaderMask ni animación corriendo', (tester) async {
      await tester.pumpWidget(_wrap(
        child: const TreinoShimmer(
          enabled: false,
          child: SizedBox(
            key: ValueKey('skeleton-box'),
            width: 120,
            height: 14,
          ),
        ),
      ));

      expect(find.byKey(const ValueKey('skeleton-box')), findsOneWidget);
      expect(find.byType(ShaderMask), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('enabled cambia en runtime → frena/arranca el loop',
        (tester) async {
      // loading (shimmer corriendo)…
      await tester.pumpWidget(_wrap(
        child: const TreinoShimmer(child: SizedBox(width: 120, height: 14)),
      ));
      expect(tester.hasRunningAnimations, isTrue);

      // …el provider falla y el caller reusa el skeleton con enabled: false.
      await tester.pumpWidget(_wrap(
        child: const TreinoShimmer(
          enabled: false,
          child: SizedBox(width: 120, height: 14),
        ),
      ));
      expect(find.byType(ShaderMask), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);

      // Retry → loading de nuevo: el loop vuelve.
      await tester.pumpWidget(_wrap(
        child: const TreinoShimmer(child: SizedBox(width: 120, height: 14)),
      ));
      expect(find.byType(ShaderMask), findsOneWidget);
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('reduce-motion cambia en runtime → frena/arranca el loop',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const TreinoShimmer(child: SizedBox(width: 120, height: 14)),
      ));
      expect(tester.hasRunningAnimations, isTrue);

      // El usuario activa reduce-motion con el skeleton montado.
      await tester.pumpWidget(_wrap(
        disableAnimations: true,
        child: const TreinoShimmer(child: SizedBox(width: 120, height: 14)),
      ));
      expect(find.byType(ShaderMask), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);

      // Y la desactiva de nuevo → el loop vuelve.
      await tester.pumpWidget(_wrap(
        child: const TreinoShimmer(child: SizedBox(width: 120, height: 14)),
      ));
      expect(find.byType(ShaderMask), findsOneWidget);
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('no leakea ticker: desmontar el widget no deja animación viva',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const TreinoShimmer(child: SizedBox(width: 120, height: 14)),
      ));
      // Loop corriendo a mitad de período.
      await tester.pump(const Duration(milliseconds: 700));

      // Desmonta el shimmer → dispose() del controller. Si el ticker
      // leakeara, el binding fallaría el test acá o en el teardown.
      await tester.pumpWidget(_wrap(child: const SizedBox.shrink()));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
