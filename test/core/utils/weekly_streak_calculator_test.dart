import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/weekly_streak_calculator.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';

import '../../fixtures/routines.dart';

// Fixtures UTC-flagged al MEDIODÍA, misma convención que
// `streak_calculator_test.dart`: mediodía UTC cae 09:00 ART, el mismo día
// calendario bajo cualquier timezone del runner (CI corre en UTC, la máquina
// de dev en ART). Nunca cruza medianoche, así que el resultado esperado no
// depende de dónde corran los tests.
//
// `wasFullyCompleted: true` es obligatorio: `status: finished` solo también
// matchea una sesión abandonada (ver Session.countsAsWorkout).
Session _finishedOn(DateTime utcDate, {String id = 's'}) => Session(
      id: id,
      uid: 'u1',
      routineId: 'r1',
      routineName: 'Test',
      startedAt: utcDate,
      status: SessionStatus.finished,
      wasFullyCompleted: true,
    );

/// [n] sesiones que califican dentro de la semana que arranca el lunes
/// [mondayUtc]. Se reparten en días distintos (lunes, martes, …) para que se
/// parezcan a datos reales; el bucketeo por semana no depende de eso.
List<Session> _weekWith(DateTime mondayUtc, int n, {required String prefix}) =>
    List.generate(
      n,
      (i) => _finishedOn(
        DateTime.utc(mondayUtc.year, mondayUtc.month, mondayUtc.day + i, 12),
        id: '$prefix-$i',
      ),
    );

/// Día del plan. `slots: 0` modela un día de descanso — un [RoutineDay] con
/// `slots` vacío es válido en el dominio (SCENARIO-046).
RoutineDay _day(int n, {int slots = 1}) => RoutineDay(
      dayNumber: n,
      name: 'Día $n',
      slots: List.filled(slots, kOneSlot),
    );

Routine _routine(List<RoutineDay> days) => Routine(
      id: 'r1',
      name: 'Plan',
      level: ExperienceLevel.beginner,
      days: days,
    );

void main() {
  // Lunes 2026-05-11. El "hoy" de casi todos los casos es el miércoles
  // 2026-05-13 (semana en curso, todavía no terminada).
  final week0 = DateTime.utc(2026, 5, 11); // semana en curso
  final week1 = DateTime.utc(2026, 5, 4); // anterior
  final week2 = DateTime.utc(2026, 4, 27);
  final week3 = DateTime.utc(2026, 4, 20);
  final wednesday = DateTime.utc(2026, 5, 13, 12);

  group('computeWeeklyStreak — la semana en curso nunca corta', () {
    test('el caso del producto: 3 semanas cumplidas y la 4ta falla → 3', () {
      // Objetivo 3/semana. Las tres semanas cerradas cumplen; la semana en
      // curso va 1 de 3 — no cumplió TODAVÍA, pero no fracasó.
      final sessions = [
        ..._weekWith(week0, 1, prefix: 'w0'),
        ..._weekWith(week1, 3, prefix: 'w1'),
        ..._weekWith(week2, 3, prefix: 'w2'),
        ..._weekWith(week3, 3, prefix: 'w3'),
      ];
      expect(
        computeWeeklyStreak(
          sessions: sessions,
          weeklyTarget: 3,
          now: wednesday,
        ),
        3,
      );
    });

    test('la semana en curso ya cumplida SÍ suma', () {
      final sessions = [
        ..._weekWith(week0, 3, prefix: 'w0'),
        ..._weekWith(week1, 3, prefix: 'w1'),
      ];
      expect(
        computeWeeklyStreak(
          sessions: sessions,
          weeklyTarget: 3,
          now: wednesday,
        ),
        2,
      );
    });

    test('semana en curso vacía no corta: cuenta desde la anterior', () {
      final sessions = [
        ..._weekWith(week1, 3, prefix: 'w1'),
        ..._weekWith(week2, 3, prefix: 'w2'),
      ];
      expect(
        computeWeeklyStreak(
          sessions: sessions,
          weeklyTarget: 3,
          now: wednesday,
        ),
        2,
      );
    });

    test('una semana cerrada incompleta corta la racha ahí', () {
      // week1 va 2 de 3 → corta. week2/week3 cumplen pero quedan del otro
      // lado del corte y no se cuentan.
      final sessions = [
        ..._weekWith(week0, 3, prefix: 'w0'),
        ..._weekWith(week1, 2, prefix: 'w1'),
        ..._weekWith(week2, 3, prefix: 'w2'),
        ..._weekWith(week3, 3, prefix: 'w3'),
      ];
      expect(
        computeWeeklyStreak(
          sessions: sessions,
          weeklyTarget: 3,
          now: wednesday,
        ),
        1,
      );
    });
  });

  group('computeWeeklyStreak — bordes', () {
    test('sin sesiones → 0', () {
      expect(
        computeWeeklyStreak(sessions: [], weeklyTarget: 3, now: wednesday),
        0,
      );
    });

    test('sesiones abandonadas no cuentan para el objetivo', () {
      final sessions = [
        ..._weekWith(week1, 2, prefix: 'w1'),
        Session(
          id: 'abandonada',
          uid: 'u1',
          routineId: 'r1',
          routineName: 'Test',
          startedAt: DateTime.utc(2026, 5, 7, 12), // dentro de week1
          status: SessionStatus.finished,
          wasFullyCompleted: false,
        ),
      ];
      // 2 reales + 1 abandonada: si la abandonada contara, daría 1.
      expect(
        computeWeeklyStreak(
          sessions: sessions,
          weeklyTarget: 3,
          now: wednesday,
        ),
        0,
      );
    });

    test('objetivo 0 degrada al fallback de 1, no cuenta semanas vacías', () {
      // Con un `>=0` crudo la racha contaría hacia atrás para siempre.
      final sessions = [..._weekWith(week1, 1, prefix: 'w1')];
      expect(
        computeWeeklyStreak(
          sessions: sessions,
          weeklyTarget: 0,
          now: wednesday,
        ),
        1,
      );
    });

    test('el borde de semana es lunes ART, no el domingo', () {
      // Domingo 2026-05-10 21:00 ART = 2026-05-11 00:00 UTC. En UTC ya es
      // lunes y caería en la semana en curso; en ART todavía es la semana
      // anterior. Con objetivo 1 y "hoy" el lunes 11, la sesión tiene que
      // bucketear en week1 → racha 1 (semana en curso vacía, no corta).
      final domingoTardeArt = DateTime.utc(2026, 5, 11, 0);
      final lunes = DateTime.utc(2026, 5, 11, 15); // 12:00 ART del lunes
      expect(
        computeWeeklyStreak(
          sessions: [_finishedOn(domingoTardeArt)],
          weeklyTarget: 1,
          now: lunes,
        ),
        1,
      );
    });
  });

  group('weeklyStreakOf — currentWeekMet (el invariante de la escritura)', () {
    // `SessionRepository.finish` persiste la racha SÓLO cuando este flag es
    // true, y de eso depende que el sello de frescura signifique "la semana
    // sellada CONTÓ". Ver `effectiveRachaSemanas`.
    test('semana en curso cumplida → true', () {
      final r = weeklyStreakOf(
        sessions: _weekWith(week0, 3, prefix: 'w0'),
        weeklyTarget: 3,
        now: wednesday,
      );
      expect(r.currentWeekMet, isTrue);
      expect(r.streak, 1);
    });

    test('semana en curso a medias → false, aunque la racha sea > 0', () {
      // Éste es el caso que rompía el decay: la racha vale 2 (viene de las dos
      // semanas anteriores) pero la semana en curso NO cumplió. Persistir acá
      // sellaba un valor heredado y lo hacía pasar por fresco una semana de
      // más.
      final r = weeklyStreakOf(
        sessions: [
          ..._weekWith(week0, 1, prefix: 'w0'),
          ..._weekWith(week1, 3, prefix: 'w1'),
          ..._weekWith(week2, 3, prefix: 'w2'),
        ],
        weeklyTarget: 3,
        now: wednesday,
      );
      expect(r.streak, 2);
      expect(r.currentWeekMet, isFalse);
    });

    test('semana en curso vacía → false', () {
      final r = weeklyStreakOf(
        sessions: _weekWith(week1, 3, prefix: 'w1'),
        weeklyTarget: 3,
        now: wednesday,
      );
      expect(r.currentWeekMet, isFalse);
    });
  });

  group('weeklyTargetFromRoutine', () {
    test('sin rutina activa → fallback 1', () {
      expect(weeklyTargetFromRoutine(null), weeklyStreakFallbackTarget);
    });

    test('cuenta los días del plan', () {
      expect(weeklyTargetFromRoutine(_routine([_day(1), _day(2), _day(3)])), 3);
    });

    test('los días sin ejercicios son descanso y NO suman al objetivo', () {
      // Un RoutineDay con slots vacío es válido en el dominio
      // (SCENARIO-046) y es como se modela el descanso. Si contara, un plan
      // de 3 días con 4 de descanso exigiría 7 sesiones por semana.
      final plan = _routine([
        _day(1),
        _day(2, slots: 0),
        _day(3),
        _day(4, slots: 0),
      ]);
      expect(weeklyTargetFromRoutine(plan), 2);
    });

    test('rutina de puros días vacíos → fallback 1', () {
      final plan = _routine([_day(1, slots: 0), _day(2, slots: 0)]);
      expect(weeklyTargetFromRoutine(plan), weeklyStreakFallbackTarget);
    });

    test('rutina sin días → fallback 1', () {
      expect(weeklyTargetFromRoutine(_routine([])), weeklyStreakFallbackTarget);
    });
  });
}
