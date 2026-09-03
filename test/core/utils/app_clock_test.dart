import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/app_clock.dart';
import 'package:treino/core/utils/argentina_time.dart';
import 'package:treino/features/coach/domain/wall_clock.dart';

/// Contrato de `AppClock` — el seam de reloj que hace fotografiable al Coach
/// Hub (#761).
///
/// Lo que estos tests protegen no es "devuelve una fecha": es que congelar el
/// reloj alcance para congelar a los DOS helpers de tiempo del repo. Si alguien
/// vuelve a poner `DateTime.now()` adentro de `argentinaNow()` o `nowWall()`,
/// el gate visual se pone flaky y nadie sabe por qué — estos tests lo dicen
/// antes.
void main() {
  tearDown(AppClock.unfreeze);

  group('AppClock', () {
    test('sin congelar es un passthrough de DateTime.now()', () {
      final antes = DateTime.now();
      final ahora = AppClock.now();
      final despues = DateTime.now();

      expect(AppClock.isFrozen, isFalse);
      expect(ahora.isBefore(antes), isFalse);
      expect(ahora.isAfter(despues), isFalse);
      expect(ahora.isUtc, isFalse, reason: 'igual que DateTime.now()');
    });

    test('congelado devuelve SIEMPRE el mismo instante', () {
      final instante = DateTime(2026, 3, 17, 10, 30, 45, 123);
      AppClock.freeze(instante);

      expect(AppClock.isFrozen, isTrue);
      expect(AppClock.now(), instante);
      expect(AppClock.now(), instante);
      expect(
        AppClock.now().microsecondsSinceEpoch,
        instante.microsecondsSinceEpoch,
        reason: 'hasta el microsegundo: los goldens comparan bytes',
      );
    });

    test('unfreeze vuelve al reloj real y es idempotente', () {
      AppClock.freeze(DateTime(2026, 3, 17, 10, 30));
      AppClock.unfreeze();
      AppClock.unfreeze();

      expect(AppClock.isFrozen, isFalse);
      expect(
        AppClock.now().difference(DateTime.now()).abs(),
        lessThan(const Duration(seconds: 5)),
      );
    });

    test('re-congelar pisa el instante anterior', () {
      final primero = DateTime(2026, 3, 17, 10, 30);
      final segundo = DateTime(2026, 12, 1, 23, 59);

      AppClock.freeze(primero);
      expect(AppClock.now(), primero);
      AppClock.freeze(segundo);
      expect(AppClock.now(), segundo);
    });

    test('freeze rechaza un DateTime UTC', () {
      expect(
        () => AppClock.freeze(DateTime.utc(2026, 3, 17, 10, 30)),
        throwsA(isA<AssertionError>()),
        reason: 'reemplaza a DateTime.now(), que devuelve local. Con un '
            'UTC-flagged, todo caller que haga .toUtc() resta el offset dos '
            'veces.',
      );
    });
  });

  group('los helpers de tiempo leen del seam', () {
    // 17/03/2026 10:30 hora local. La máquina de CI corre en UTC, la del dev
    // en ART: por eso las aserciones de abajo se derivan del instante, no de
    // constantes escritas a mano.
    final instante = DateTime(2026, 3, 17, 10, 30);

    test('argentinaNow() se congela con AppClock', () {
      AppClock.freeze(instante);

      final esperado = instante.toUtc().subtract(argentinaUtcOffset);
      expect(argentinaNow(), esperado);
      expect(argentinaNow(), argentinaNow(), reason: 'estable entre llamadas');
    });

    test('nowWall() sin argumento se congela con AppClock', () {
      AppClock.freeze(instante);

      expect(nowWall(), DateTime.utc(2026, 3, 17, 10, 30));
      expect(
        nowWall().isUtc,
        isTrue,
        reason: 'wall-clock ADR-7: campos locales, flag UTC',
      );
    });

    test('nowWall(now:) explícito sigue ganándole al seam', () {
      AppClock.freeze(instante);

      expect(
        nowWall(now: DateTime(2026, 1, 2, 3, 4)),
        DateTime.utc(2026, 1, 2, 3, 4),
        reason:
            'el parámetro por call-site existía antes del seam y no lo pisa: '
            'los tests que ya lo usan no cambian de comportamiento',
      );
    });
  });
}
