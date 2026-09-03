// Tests del rollup de la serie de bienestar (#643 slice 3).
//
// Es donde viven las decisiones discutibles del slice — promediar el día,
// ORear el dolor, contar registros y no días para el ratio, partir las dos
// ventanas por clave de fecha — así que se testean en función pura, sin
// Firestore ni emulador de por medio.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/checkins/domain/check_in.dart';
import 'package:treino/features/insights/application/wellbeing_trend_aggregator.dart';
import 'package:treino/features/insights/domain/wellbeing_trend.dart';
import 'package:treino/features/workout/domain/muscle_group.dart';

CheckIn _c(
  String date, {
  CheckInFeeling feeling = CheckInFeeling.normal,
  bool hasPain = false,
  List<MuscleGroup> painAreas = const [],
  String? sessionId,
}) =>
    CheckIn(
      id: '${date}_1',
      date: date,
      feeling: feeling,
      hasPain: hasPain,
      painAreas: painAreas,
      recordedAt: DateTime.utc(2026, 5, 18),
      sessionId: sessionId,
    );

void main() {
  group('ventana vacía', () {
    test('sin check-ins devuelve la serie vacía', () {
      expect(
        aggregateWellbeingTrend(const [], currentStart: '2026-05-01'),
        emptyWellbeingTrend,
      );
    });

    test(
        'sólo registros de la ventana anterior: la curva queda vacía pero '
        'el conteo anterior no', () {
      final trend = aggregateWellbeingTrend(
        [_c('2026-04-10', hasPain: true), _c('2026-04-11')],
        currentStart: '2026-05-01',
      );

      expect(trend.points, isEmpty);
      expect(trend.recordCount, 0);
      expect(trend.previousRecordCount, 2);
      expect(trend.previousPainCount, 1);
    });
  });

  group('un punto por día', () {
    test('los días con registro salen ordenados del más viejo al más nuevo',
        () {
      final trend = aggregateWellbeingTrend(
        [_c('2026-05-20'), _c('2026-05-03'), _c('2026-05-11')],
        currentStart: '2026-05-01',
      );

      expect(
        trend.points.map((p) => p.date),
        ['2026-05-03', '2026-05-11', '2026-05-20'],
      );
    });

    test('dos registros el mismo día se PROMEDIAN en un punto', () {
      // Desde #643 el id del documento dejó de ser la fecha, así que un día
      // puede traer el del entreno y el diario. La curva es por día.
      final trend = aggregateWellbeingTrend(
        [
          _c('2026-05-03', feeling: CheckInFeeling.muyMal, sessionId: 's1'),
          _c('2026-05-03', feeling: CheckInFeeling.muyBien),
        ],
        currentStart: '2026-05-01',
      );

      expect(trend.points, hasLength(1));
      // muyMal = 0, muyBien = 4 -> 2.0
      expect(trend.points.single.feelingLevel, 2.0);
      // Pero el ratio de dolor cuenta REGISTROS, no días.
      expect(trend.recordCount, 2);
    });

    test('el dolor del día es un OR, no un promedio', () {
      // Un día con dolor no deja de tenerlo porque el otro registro del día
      // no lo reportara.
      final trend = aggregateWellbeingTrend(
        [
          _c('2026-05-03', hasPain: true, painAreas: [MuscleGroup.espalda]),
          _c('2026-05-03'),
        ],
        currentStart: '2026-05-01',
      );

      expect(trend.points.single.hadPain, isTrue);
      expect(trend.painCount, 1);
    });
  });

  group('corte entre ventanas', () {
    test('el día exacto de currentStart cae en la ventana ACTUAL', () {
      final trend = aggregateWellbeingTrend(
        [_c('2026-05-01'), _c('2026-04-30')],
        currentStart: '2026-05-01',
      );

      expect(trend.recordCount, 1);
      expect(trend.points.single.date, '2026-05-01');
      expect(trend.previousRecordCount, 1);
    });

    test('los conteos de dolor de cada ventana no se mezclan', () {
      final trend = aggregateWellbeingTrend(
        [
          _c('2026-04-02', hasPain: true),
          _c('2026-04-03', hasPain: true),
          _c('2026-04-04'),
          _c('2026-05-02', hasPain: true),
          _c('2026-05-03'),
        ],
        currentStart: '2026-05-01',
      );

      expect(trend.painCount, 1);
      expect(trend.recordCount, 2);
      expect(trend.previousPainCount, 2);
      expect(trend.previousRecordCount, 3);
    });
  });

  group('zonas', () {
    test('cuenta registros por zona, de la más registrada a la menos', () {
      final trend = aggregateWellbeingTrend(
        [
          _c('2026-05-02',
              hasPain: true,
              painAreas: [MuscleGroup.espalda, MuscleGroup.cuadriceps]),
          _c('2026-05-03', hasPain: true, painAreas: [MuscleGroup.espalda]),
          _c('2026-05-04', hasPain: true, painAreas: [MuscleGroup.espalda]),
        ],
        currentStart: '2026-05-01',
      );

      expect(trend.painByArea.first.area, MuscleGroup.espalda);
      expect(trend.painByArea.first.count, 3);
      expect(trend.painByArea.last.area, MuscleGroup.cuadriceps);
      expect(trend.painByArea.last.count, 1);
    });

    test('empate de conteo: desempata el orden canónico de MuscleGroup', () {
      // Sin desempate estable la lista baila entre renders sin que haya
      // cambiado ningún dato.
      final trend = aggregateWellbeingTrend(
        [
          _c('2026-05-02', hasPain: true, painAreas: [MuscleGroup.cuadriceps]),
          _c('2026-05-03', hasPain: true, painAreas: [MuscleGroup.espalda]),
        ],
        currentStart: '2026-05-01',
      );

      final expected = MuscleGroup.displayOrder
          .where((g) => g == MuscleGroup.espalda || g == MuscleGroup.cuadriceps)
          .toList();
      expect(trend.painByArea.map((e) => e.area), expected);
    });

    test('la misma zona repetida en un registro cuenta una vez', () {
      final trend = aggregateWellbeingTrend(
        [
          _c('2026-05-02', hasPain: true, painAreas: [
            MuscleGroup.espalda,
            MuscleGroup.espalda,
          ]),
        ],
        currentStart: '2026-05-01',
      );

      expect(trend.painByArea.single.count, 1);
    });

    test('las zonas de un registro SIN dolor se ignoran', () {
      // hasPain false con zonas cargadas es un doc inconsistente; manda el
      // flag, que es lo que el usuario respondió.
      final trend = aggregateWellbeingTrend(
        [
          _c('2026-05-02', painAreas: [MuscleGroup.espalda])
        ],
        currentStart: '2026-05-01',
      );

      expect(trend.painByArea, isEmpty);
      expect(trend.painCount, 0);
      expect(trend.recordCount, 1);
    });
  });
}
