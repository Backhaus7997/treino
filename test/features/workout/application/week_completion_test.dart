// Tests de deriveWeekCompletion + sessionWeekCompletionProvider — cuándo el
// resumen post-entreno felicita con "Semana cumplida". Cada regla con su caso,
// el objetivo de fallback y los bordes de semana ART.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/app_clock.dart';
import 'package:treino/core/utils/weekly_streak_calculator.dart';
import 'package:treino/features/home/application/todays_routine_provider.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/application/week_completion.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';

import '../../../fixtures/routines.dart';

Session _session(
  String id,
  DateTime startedAt, {
  bool counts = true,
}) =>
    Session(
      id: id,
      uid: 'u1',
      routineId: 'r1',
      routineName: 'Push',
      startedAt: startedAt,
      // `finished` solo también matchea una sesión abandonada: lo que decide si
      // cuenta es `wasFullyCompleted` (#372, ver Session.countsAsWorkout).
      status: SessionStatus.finished,
      wasFullyCompleted: counts,
    );

/// [n] sesiones que cuentan en la semana ART que arranca el lunes [mondayUtc],
/// al mediodía UTC (09:00 ART): mismo día calendario bajo cualquier timezone del
/// runner y sin cruzar nunca la medianoche.
List<Session> _week(DateTime mondayUtc, int n, {required String prefix}) =>
    List.generate(
      n,
      (i) => _session(
        '$prefix-$i',
        DateTime.utc(mondayUtc.year, mondayUtc.month, mondayUtc.day + i, 12),
      ),
    );

void main() {
  // La semana en curso de casi todos los casos es la que arranca el lunes
  // 2026-05-18; "hoy" es el miércoles 20 a las 12:00 ART (15:00 UTC). Las
  // anteriores se identifican por su lunes.
  final week1 = DateTime.utc(2026, 5, 11);
  final week2 = DateTime.utc(2026, 5, 4);
  final week3 = DateTime.utc(2026, 4, 27);
  final wednesday = DateTime.utc(2026, 5, 20, 15);

  group('deriveWeekCompletion', () {
    test('la sesión que completa el objetivo (3 de 3) felicita con la racha',
        () {
      final session = _session('s-wed', DateTime.utc(2026, 5, 20, 12));
      final result = deriveWeekCompletion(
        session: session,
        sessionsDesc: [
          session,
          _session('s-tue', DateTime.utc(2026, 5, 19, 12)),
          _session('s-mon', DateTime.utc(2026, 5, 18, 12)),
          // Dos semanas anteriores cumplidas: la racha es 1 + 2.
          ..._week(week1, 3, prefix: 'w1'),
          ..._week(week2, 3, prefix: 'w2'),
        ],
        weeklyTarget: 3,
        now: wednesday,
      );

      expect(result, (streak: 3));
    });

    test('la sesión recién cerrada puede no estar todavía en la lista', () {
      final session = _session('s-wed', DateTime.utc(2026, 5, 20, 12));
      final result = deriveWeekCompletion(
        session: session,
        // Sin `session`: el fetch llegó antes de que el cierre se viera.
        sessionsDesc: [
          _session('s-tue', DateTime.utc(2026, 5, 19, 12)),
          _session('s-mon', DateTime.utc(2026, 5, 18, 12)),
          ..._week(week1, 3, prefix: 'w1'),
        ],
        weeklyTarget: 3,
        now: wednesday,
      );

      expect(result, (streak: 2));
    });

    test('primera semana cumplida de la corrida → racha 1', () {
      final session = _session('s-wed', DateTime.utc(2026, 5, 20, 12));
      final result = deriveWeekCompletion(
        session: session,
        sessionsDesc: [
          session,
          _session('s-tue', DateTime.utc(2026, 5, 19, 12)),
          _session('s-mon', DateTime.utc(2026, 5, 18, 12)),
        ],
        weeklyTarget: 3,
        now: wednesday,
      );

      expect(result, (streak: 1));
    });

    test('una semana anterior incumplida corta la racha ahí', () {
      final session = _session('s-wed', DateTime.utc(2026, 5, 20, 12));
      final result = deriveWeekCompletion(
        session: session,
        sessionsDesc: [
          session,
          _session('s-tue', DateTime.utc(2026, 5, 19, 12)),
          _session('s-mon', DateTime.utc(2026, 5, 18, 12)),
          // week1 va 2 de 3: corta. week2 y week3 cumplen pero quedan del otro
          // lado del corte.
          ..._week(week1, 2, prefix: 'w1'),
          ..._week(week2, 3, prefix: 'w2'),
          ..._week(week3, 3, prefix: 'w3'),
        ],
        weeklyTarget: 3,
        now: wednesday,
      );

      expect(result, (streak: 1));
    });

    test('la sesión siguiente, ya cumplido el objetivo, NO felicita de nuevo',
        () {
      final cuarta = _session('s-thu', DateTime.utc(2026, 5, 21, 12));
      final result = deriveWeekCompletion(
        session: cuarta,
        sessionsDesc: [
          cuarta,
          _session('s-wed', DateTime.utc(2026, 5, 20, 12)),
          _session('s-tue', DateTime.utc(2026, 5, 19, 12)),
          _session('s-mon', DateTime.utc(2026, 5, 18, 12)),
        ],
        weeklyTarget: 3,
        now: wednesday,
      );

      expect(result, isNull);
    });

    test(
        'ver la sesión que cumplió, con otra posterior ya hecha, sigue '
        'felicitando: describe lo que era cierto AL completarla', () {
      final tercera = _session('s-wed', DateTime.utc(2026, 5, 20, 12));
      final result = deriveWeekCompletion(
        session: tercera,
        sessionsDesc: [
          _session('s-thu', DateTime.utc(2026, 5, 21, 12)),
          tercera,
          _session('s-tue', DateTime.utc(2026, 5, 19, 12)),
          _session('s-mon', DateTime.utc(2026, 5, 18, 12)),
        ],
        weeklyTarget: 3,
        now: DateTime.utc(2026, 5, 21, 15),
      );

      expect(result, (streak: 1));
    });

    test('por debajo del objetivo (2 de 3) todavía no hay nada que celebrar',
        () {
      final session = _session('s-tue', DateTime.utc(2026, 5, 19, 12));
      final result = deriveWeekCompletion(
        session: session,
        sessionsDesc: [
          session,
          _session('s-mon', DateTime.utc(2026, 5, 18, 12)),
        ],
        weeklyTarget: 3,
        now: wednesday,
      );

      expect(result, isNull);
    });

    test('una sesión que no cuenta (#372) no felicita, aunque fuera la 3ª', () {
      final abandonada = _session(
        's-wed',
        DateTime.utc(2026, 5, 20, 12),
        counts: false,
      );
      final result = deriveWeekCompletion(
        session: abandonada,
        sessionsDesc: [
          abandonada,
          _session('s-tue', DateTime.utc(2026, 5, 19, 12)),
          _session('s-mon', DateTime.utc(2026, 5, 18, 12)),
        ],
        weeklyTarget: 3,
        now: wednesday,
      );

      expect(result, isNull);
    });

    test('las abandonadas de la semana no suman al objetivo', () {
      final session = _session('s-wed', DateTime.utc(2026, 5, 20, 12));
      final result = deriveWeekCompletion(
        session: session,
        sessionsDesc: [
          session,
          // Tres sesiones en la semana, pero una abandonada: son 2 de 3.
          _session('s-tue', DateTime.utc(2026, 5, 19, 12), counts: false),
          _session('s-mon', DateTime.utc(2026, 5, 18, 12)),
        ],
        weeklyTarget: 3,
        now: wednesday,
      );

      expect(result, isNull);
    });

    test('una semana vieja no se felicita: el botón lleva a la semana actual',
        () {
      // La sesión SÍ completó el objetivo de SU semana (week1)...
      final session = _session('s-wed', DateTime.utc(2026, 5, 13, 12));
      final result = deriveWeekCompletion(
        session: session,
        sessionsDesc: [
          session,
          _session('s-tue', DateTime.utc(2026, 5, 12, 12)),
          _session('s-mon', DateTime.utc(2026, 5, 11, 12)),
        ],
        weeklyTarget: 3,
        // ...pero hoy es otra semana.
        now: wednesday,
      );

      expect(result, isNull);
    });

    group('objetivo de fallback', () {
      test('con objetivo 1 la primera sesión de la semana cumple', () {
        final session = _session('s-mon', DateTime.utc(2026, 5, 18, 12));
        final result = deriveWeekCompletion(
          session: session,
          sessionsDesc: [session],
          weeklyTarget: weeklyStreakFallbackTarget,
          now: wednesday,
        );

        expect(result, (streak: 1));
      });

      test('con objetivo 1 la segunda sesión de la semana ya no felicita', () {
        final segunda = _session('s-tue', DateTime.utc(2026, 5, 19, 12));
        final result = deriveWeekCompletion(
          session: segunda,
          sessionsDesc: [
            segunda,
            _session('s-mon', DateTime.utc(2026, 5, 18, 12)),
          ],
          weeklyTarget: weeklyStreakFallbackTarget,
          now: wednesday,
        );

        expect(result, isNull);
      });

      test('un objetivo <= 0 se trata como el fallback, no como "siempre"', () {
        final segunda = _session('s-tue', DateTime.utc(2026, 5, 19, 12));
        final sessions = [
          segunda,
          _session('s-mon', DateTime.utc(2026, 5, 18, 12)),
        ];

        // Con 0 tomado literal, `1 == 0` nunca da verdadero y la primera
        // sesión no celebraría; con el fallback (1) celebra solo la primera.
        expect(
          deriveWeekCompletion(
            session: sessions.last,
            sessionsDesc: sessions,
            weeklyTarget: 0,
            now: wednesday,
          ),
          (streak: 1),
        );
        expect(
          deriveWeekCompletion(
            session: segunda,
            sessionsDesc: sessions,
            weeklyTarget: 0,
            now: wednesday,
          ),
          isNull,
        );
      });
    });

    group('borde de semana ART (lunes-domingo, no UTC)', () {
      // Domingo 2026-05-24 23:30 ART = lunes 2026-05-25 02:30 UTC.
      final sundayLate = DateTime.utc(2026, 5, 25, 2, 30);
      // Lunes 2026-05-25 00:30 ART = 03:30 UTC.
      final mondayEarly = DateTime.utc(2026, 5, 25, 3, 30);

      test(
          'domingo 23:30 ART es de la semana que cierra, aunque en UTC sea '
          'lunes', () {
        final session = _session('s-dom', sundayLate);
        final result = deriveWeekCompletion(
          session: session,
          sessionsDesc: [
            session,
            _session('s-lun', DateTime.utc(2026, 5, 18, 12)),
          ],
          weeklyTarget: 2,
          // Domingo 23:45 ART: la semana en curso sigue siendo la de la sesión.
          now: DateTime.utc(2026, 5, 25, 2, 45),
        );

        // En UTC la sesión caería sola en la semana siguiente (1 de 2).
        expect(result, (streak: 1));
      });

      test(
          'lunes 00:30 ART ya es la semana nueva, aunque haya una sesión 1 h '
          'antes', () {
        final session = _session('s-lun', mondayEarly);
        final result = deriveWeekCompletion(
          session: session,
          sessionsDesc: [
            session,
            // Domingo 23:30 ART: semana ANTERIOR. En UTC las dos serían del
            // mismo lunes y la sesión "cumpliría" 2 de 2.
            _session('s-dom', sundayLate),
          ],
          weeklyTarget: 2,
          now: DateTime.utc(2026, 5, 25, 4),
        );

        expect(result, isNull);
      });

      test(
          'la sesión del domingo 23:30 ART, vista ya pasada la medianoche, '
          'no felicita', () {
        final session = _session('s-dom', sundayLate);
        final result = deriveWeekCompletion(
          session: session,
          sessionsDesc: [
            session,
            _session('s-lun', DateTime.utc(2026, 5, 18, 12)),
          ],
          weeklyTarget: 2,
          // Lunes 00:30 ART: la semana de la sesión ya no es la en curso.
          now: mondayEarly,
        );

        expect(result, isNull);
      });
    });

    group('reloj', () {
      tearDown(AppClock.unfreeze);

      test('sin `now` usa AppClock (la semana en curso se puede congelar)', () {
        final session = _session('s-wed', DateTime.utc(2026, 5, 20, 12));
        final sessions = [
          session,
          _session('s-tue', DateTime.utc(2026, 5, 19, 12)),
          _session('s-mon', DateTime.utc(2026, 5, 18, 12)),
        ];

        // `freeze` espera local-flagged: el mismo instante, sin depender de la
        // timezone del runner.
        AppClock.freeze(wednesday.toLocal());
        expect(
          deriveWeekCompletion(
            session: session,
            sessionsDesc: sessions,
            weeklyTarget: 3,
          ),
          (streak: 1),
        );

        // Una semana después la sesión es de una semana vieja.
        AppClock.freeze(DateTime.utc(2026, 5, 27, 15).toLocal());
        expect(
          deriveWeekCompletion(
            session: session,
            sessionsDesc: sessions,
            weeklyTarget: 3,
          ),
          isNull,
        );
      });
    });
  });

  group('sessionWeekCompletionProvider', () {
    const key = (uid: 'u1', sessionId: 's-wed');

    tearDown(AppClock.unfreeze);

    RoutineDay day(int n) => RoutineDay(
          dayNumber: n,
          name: 'Día $n',
          slots: const [kOneSlot],
        );

    TodaysRoutine routineOf(int days) {
      final routine = Routine(
        id: 'r1',
        name: 'Plan',
        level: ExperienceLevel.beginner,
        days: [for (var i = 1; i <= days; i++) day(i)],
      );
      return (
        routine: routine,
        day: routine.days.first,
        dayNumber: 1,
        weekNumber: 0,
      );
    }

    ProviderContainer containerWith({
      required Session session,
      required List<Session> sessions,
      required Future<TodaysRoutine?> Function() routine,
    }) {
      final container = ProviderContainer(
        overrides: [
          sessionSummaryProvider.overrideWith(
            (ref, _) async => (session: session, setLogs: <SetLog>[]),
          ),
          sessionsByUidProvider.overrideWith((ref, uid) async => sessions),
          todaysRoutineProvider.overrideWith((ref) => routine()),
        ],
      );
      addTearDown(container.dispose);
      // autoDispose: sin un listener el provider se descarta a mitad de vuelo.
      container.listen(sessionWeekCompletionProvider(key), (_, __) {});
      return container;
    }

    test('NO usa el fallback de 1 mientras la rutina carga: sin falso positivo',
        () async {
      AppClock.freeze(wednesday.toLocal());
      // Primera sesión de la semana de un atleta de 3 días: con el fallback
      // (1) "cumpliría" la semana; con su objetivo real (3), no.
      final session = _session('s-wed', DateTime.utc(2026, 5, 20, 12));
      final routine = Completer<TodaysRoutine?>();
      final container = containerWith(
        session: session,
        sessions: [session],
        routine: () => routine.future,
      );

      // Dejá correr los futures ya resueltos: lo único pendiente es la rutina.
      await pumpEventQueue();
      expect(
        container.read(sessionWeekCompletionProvider(key)).isLoading,
        isTrue,
        reason: 'mientras la rutina carga no hay resultado, ni siquiera el del '
            'fallback',
      );

      routine.complete(routineOf(3));
      expect(
        await container.read(sessionWeekCompletionProvider(key).future),
        isNull,
      );
    });

    test('con la rutina resuelta felicita en la sesión que cumple el objetivo',
        () async {
      AppClock.freeze(wednesday.toLocal());
      final session = _session('s-wed', DateTime.utc(2026, 5, 20, 12));
      final container = containerWith(
        session: session,
        sessions: [
          session,
          _session('s-tue', DateTime.utc(2026, 5, 19, 12)),
          _session('s-mon', DateTime.utc(2026, 5, 18, 12)),
        ],
        routine: () async => routineOf(3),
      );

      expect(
        await container.read(sessionWeekCompletionProvider(key).future),
        (streak: 1),
      );
    });

    test('sin rutina activa el objetivo es el fallback (1)', () async {
      AppClock.freeze(wednesday.toLocal());
      final session = _session('s-wed', DateTime.utc(2026, 5, 20, 12));
      final container = containerWith(
        session: session,
        sessions: [session],
        routine: () async => null,
      );

      expect(
        await container.read(sessionWeekCompletionProvider(key).future),
        (streak: 1),
      );
    });

    test('uid vacío → null, sin tocar ningún provider', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        await container.read(
          sessionWeekCompletionProvider((uid: '', sessionId: 's')).future,
        ),
        isNull,
      );
    });
  });
}
