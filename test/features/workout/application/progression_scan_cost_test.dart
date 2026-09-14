// El invariante de COSTO de `athleteExerciseListProvider`.
//
// Ese provider escanea desde el `currentStart` más antiguo de los períodos que
// mira, y por cada sesión escaneada hace un read de `setLogs`. Si un período
// largo participara de ese ensanchamiento, abrir la pantalla de progresión
// escanearía un año de sesiones —cientos de reads— para TODO el mundo,
// incluido quien nunca va a tocar ese período.
//
// Este archivo no testea un widget ni un provider: pinea la REGLA que evita
// esa regresión, para que agregar el próximo período largo no la rompa en
// silencio.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/insights/domain/chart_period.dart';
import 'package:treino/features/workout/application/exercise_progression_providers.dart';

void main() {
  group('kScanWideningPeriods', () {
    test('los períodos largos NO ensanchan el scan', () {
      expect(kScanWideningPeriods.contains(ChartPeriod.last3m), isFalse);
      expect(kScanWideningPeriods.contains(ChartPeriod.last1y), isFalse);
    });

    test('los tres cortos SÍ ensanchan — su ventana tiene que estar cubierta',
        () {
      expect(kScanWideningPeriods, {
        ChartPeriod.last30d,
        ChartPeriod.thisWeek,
        ChartPeriod.month,
      });
    });

    test('el período por defecto siempre ensancha', () {
      // Si el default quedara afuera, la pantalla abriría con un scan que no
      // cubre su propia ventana y faltarían ejercicios en el picker.
      expect(kScanWideningPeriods.contains(ChartPeriod.defaultPeriod), isTrue);
    });

    test('ningún período que ensancha mira más atrás que ~31 días', () {
      // El techo real del costo de abrir la pantalla. Si alguien agrega un
      // período de 6 meses al set de ensanchamiento, este test lo frena.
      final now = DateTime.utc(2026, 9, 15);
      final limite = DateTime.utc(2026, 9, 15 - 31);
      for (final p in kScanWideningPeriods) {
        final start = p.windowFor(now).currentStart;
        expect(start.isBefore(limite), isFalse,
            reason: '$p arranca en $start, antes del techo de 31 días');
      }
    });

    test('todo período que ensancha es un período real', () {
      expect(
          ChartPeriod.values.toSet().containsAll(kScanWideningPeriods), isTrue);
    });
  });

  group('los períodos largos igual sirven un gráfico correcto', () {
    test('su ventana es más ancha que la de cualquiera que ensancha', () {
      // El gráfico de un período largo lo arma `exerciseProgressionProvider`,
      // que sí ensancha por el período ELEGIDO. Así que quien selecciona 1 año
      // ve el año completo — y paga ese scan sólo cuando lo pide. Este test
      // documenta esa asimetría: la ventana larga existe y es más ancha; lo
      // que no hace es cobrársela a quien no la pidió.
      final now = DateTime.utc(2026, 9, 15);
      final masAntiguoQueEnsancha = kScanWideningPeriods
          .map((p) => p.windowFor(now).currentStart)
          .reduce((a, b) => a.isBefore(b) ? a : b);

      for (final largo in [ChartPeriod.last3m, ChartPeriod.last1y]) {
        expect(
          largo.windowFor(now).currentStart.isBefore(masAntiguoQueEnsancha),
          isTrue,
          reason: '$largo debería mirar más atrás que los cortos',
        );
      }
    });
  });
}
