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

  group('AppMotion curvas', () {
    // Las curvas built-in de Flutter son flojas para UI. Lo que las separa se
    // ve en el primer cuarto de la animación, que es donde el ojo decide si
    // algo respondió rápido: `standard` ya recorrió el 78% del camino y
    // `easeOutCubic` apenas el 60%. Esa diferencia es todo el cambio — así que
    // se fija con números, no con el nombre de la constante.
    test('standard es mucho más fuerte que la easeOutCubic que reemplazó', () {
      expect(AppMotion.standard.transform(0.25), greaterThan(0.75));
      expect(Curves.easeOutCubic.transform(0.25), lessThan(0.62));
    });

    test('standard a la mitad ya está prácticamente asentada', () {
      expect(AppMotion.standard.transform(0.5), greaterThan(0.95));
    });

    test('standard empieza y termina donde debe', () {
      expect(AppMotion.standard.transform(0), 0);
      expect(AppMotion.standard.transform(1), 1);
    });

    test(
        'emphasized arranca casi quieta — es para movimiento que el ojo sigue, '
        'no para una entrada', () {
      expect(AppMotion.emphasized.transform(0.1), lessThan(0.05));
      expect(
        AppMotion.emphasized.transform(0.25),
        lessThan(AppMotion.standard.transform(0.25)),
      );
    });

    test('emphasized cierra fuerte: al 75% del tiempo, >95% del camino', () {
      expect(AppMotion.emphasized.transform(0.75), greaterThan(0.95));
    });

    // `exit` sólo alimenta `switchOutCurve`, donde el controller va de 1 a 0.
    // Con `t³` sobre un parámetro que baja, la opacidad cae rápido y después
    // se apaga despacio: el que se va libera la escena enseguida. Si alguien
    // la "corrige" a una ease-out, esto se pone rojo.
    test('exit hace que el saliente se vaya rápido (t=0.5 → <0.2)', () {
      expect(AppMotion.exit.transform(0.5), lessThan(0.2));
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
