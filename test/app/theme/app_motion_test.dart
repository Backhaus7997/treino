import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_motion.dart';

void main() {
  group('AppMotion duraciones', () {
    test('la escala expone los valores del sistema', () {
      expect(AppMotion.micro, const Duration(milliseconds: 120));
      expect(AppMotion.fast, const Duration(milliseconds: 180));
      expect(AppMotion.base, const Duration(milliseconds: 240));
      expect(AppMotion.slow, const Duration(milliseconds: 320));
    });
  });

  group('AppMotion.stagger', () {
    test('el ítem 0 no tiene delay', () {
      expect(AppMotion.stagger(0), Duration.zero);
    });

    test('cada ítem suma un staggerStep (40ms)', () {
      expect(AppMotion.stagger(3), const Duration(milliseconds: 120));
    });

    test('capa el delay a maxItems default 8 (7 * 40ms)', () {
      expect(AppMotion.stagger(20), const Duration(milliseconds: 280));
    });

    test('respeta maxItems custom (maxItems: 3 → 2 * 40ms)', () {
      expect(
        AppMotion.stagger(5, maxItems: 3),
        const Duration(milliseconds: 80),
      );
    });
  });

  group('AppMotion.resolve + reduceMotion', () {
    testWidgets('con disableAnimations: true resuelve a Duration.zero',
        (tester) async {
      late bool reduce;
      late Duration resolved;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              reduce = AppMotion.reduceMotion(context);
              resolved = AppMotion.resolve(context, AppMotion.base);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(reduce, isTrue);
      expect(resolved, Duration.zero);
    });

    testWidgets('con disableAnimations: false devuelve la duración original',
        (tester) async {
      late bool reduce;
      late Duration resolved;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Builder(
            builder: (context) {
              reduce = AppMotion.reduceMotion(context);
              resolved = AppMotion.resolve(context, AppMotion.base);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(reduce, isFalse);
      expect(resolved, AppMotion.base);
    });
  });
}
