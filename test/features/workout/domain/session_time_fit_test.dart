// #645 — planSessionTimeFit: qué se saca de la sesión de HOY para que entre
// en el tiempo que el atleta declaró tener.
//
// Los slots de estos tests usan `durationSeconds` + `restSeconds: 0` a
// propósito: así cada ejercicio vale EXACTAMENTE los minutos que dice su
// nombre y toda la aritmética del archivo se lee de un vistazo. La cascada de
// estimación en sí ya está cubierta en routine_day_duration_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/session_time_fit.dart';

import '../application/stub_factories.dart';

/// Un ejercicio que dura exactamente [minutes] minutos.
RoutineSlot _slot(
  String id, {
  required int minutes,
  int? supersetGroup,
  List<int> activeWeeks = const [],
}) =>
    makeSlot(
      exerciseId: id,
      exerciseName: id,
      targetSets: 1,
      restSeconds: 0,
      durationSeconds: minutes * 60,
      supersetGroup: supersetGroup,
      activeWeeks: activeWeeks,
    );

RoutineDay _day(List<RoutineSlot> slots, {int? estimatedMinutes}) =>
    makeDay(slots: slots, estimatedMinutes: estimatedMinutes);

void main() {
  group('planSessionTimeFit', () {
    test('la sesión ya entra en el tiempo declarado → no propone nada', () {
      final plan = planSessionTimeFit(
        day: _day([
          _slot('e1', minutes: 10),
          _slot('e2', minutes: 10),
          _slot('e3', minutes: 10),
        ]),
        availableMinutes: 40,
      );

      expect(plan.outcome, SessionTimeFitOutcome.alreadyFits);
      expect(plan.currentMinutes, 30);
      expect(plan.projectedMinutes, 30);
      expect(plan.dropExerciseIds, isEmpty);
    });

    test('el borde exacto (dura lo mismo que el tiempo declarado) ya entra',
        () {
      final plan = planSessionTimeFit(
        day: _day([_slot('e1', minutes: 20), _slot('e2', minutes: 20)]),
        availableMinutes: 40,
      );

      expect(plan.outcome, SessionTimeFitOutcome.alreadyFits);
      expect(plan.dropExerciseIds, isEmpty);
    });

    test('65 min con 40 disponibles → saca los dos últimos y proyecta 39', () {
      final plan = planSessionTimeFit(
        day: _day([
          _slot('e1', minutes: 13),
          _slot('e2', minutes: 13),
          _slot('e3', minutes: 13),
          _slot('e4', minutes: 13),
          _slot('e5', minutes: 13),
        ]),
        availableMinutes: 40,
      );

      expect(plan.outcome, SessionTimeFitOutcome.trimSuggested);
      expect(plan.currentMinutes, 65);
      expect(plan.projectedMinutes, 39);
      // En orden del día, no en orden de salida.
      expect(plan.dropExerciseIds, ['e4', 'e5']);
    });

    test('saca lo MÍNIMO: con 52 disponibles sale uno solo, no dos', () {
      final plan = planSessionTimeFit(
        day: _day([
          _slot('e1', minutes: 13),
          _slot('e2', minutes: 13),
          _slot('e3', minutes: 13),
          _slot('e4', minutes: 13),
          _slot('e5', minutes: 13),
        ]),
        availableMinutes: 52,
      );

      expect(plan.outcome, SessionTimeFitOutcome.trimSuggested);
      expect(plan.dropExerciseIds, ['e5']);
      expect(plan.projectedMinutes, 52);
    });

    test('el corte no parte una superserie: sale el grupo entero', () {
      final plan = planSessionTimeFit(
        day: _day([
          _slot('e1', minutes: 20),
          _slot('e2', minutes: 10, supersetGroup: 1),
          _slot('e3', minutes: 10, supersetGroup: 1),
        ]),
        // Elegido a propósito para que el corte a medias ENTRE: sacando sólo
        // e3 quedan 30 min, que caben en 32. Sin la regla de bloque, ése sería
        // el recorte "mínimo" y el atleta terminaría haciendo media superserie
        // —que es otro estímulo de entrenamiento, no la misma superserie más
        // corta. Con la regla, sale el grupo entero y quedan 20.
        availableMinutes: 32,
      );

      expect(plan.outcome, SessionTimeFitOutcome.trimSuggested);
      expect(plan.dropExerciseIds, ['e2', 'e3']);
      expect(plan.projectedMinutes, 20);
    });

    test('un slot con supersetGroup pero sin compañero corta como standalone',
        () {
      final plan = planSessionTimeFit(
        day: _day([
          _slot('e1', minutes: 20),
          _slot('e2', minutes: 20, supersetGroup: 1),
          _slot('e3', minutes: 20, supersetGroup: 2),
        ]),
        availableMinutes: 45,
      );

      expect(plan.outcome, SessionTimeFitOutcome.trimSuggested);
      expect(plan.dropExerciseIds, ['e3']);
      expect(plan.projectedMinutes, 40);
    });

    test('nunca deja la sesión en cero: un día de un solo ejercicio no se toca',
        () {
      final plan = planSessionTimeFit(
        day: _day([_slot('e1', minutes: 60)]),
        availableMinutes: 20,
      );

      expect(plan.outcome, SessionTimeFitOutcome.cannotFit);
      expect(plan.dropExerciseIds, isEmpty);
      expect(plan.projectedMinutes, isNull);
      expect(plan.currentMinutes, 60);
    });

    test('un día que es una sola superserie no se recorta ni se rompe', () {
      // El recorrido nunca llega al slot 0 (siempre queda trabajo), y por eso
      // `_cutSplitsSuperset` puede mirar el slot anterior sin indexar en -1.
      final plan = planSessionTimeFit(
        day: _day([
          _slot('e1', minutes: 30, supersetGroup: 1),
          _slot('e2', minutes: 30, supersetGroup: 1),
        ]),
        availableMinutes: 10,
      );

      expect(plan.outcome, SessionTimeFitOutcome.cannotFit);
      expect(plan.dropExerciseIds, isEmpty);
      expect(plan.projectedMinutes, isNull);
    });

    test('frena en el primer ejercicio con series hechas — cola contigua', () {
      final plan = planSessionTimeFit(
        day: _day([
          _slot('e1', minutes: 13),
          _slot('e2', minutes: 13),
          _slot('e3', minutes: 13),
          _slot('e4', minutes: 13),
        ]),
        availableMinutes: 20,
        lockedExerciseIds: const {'e3'},
      );

      // e4 sale; e3 traba el recorrido y e2 queda fuera de alcance aunque
      // sacarlo haría entrar la sesión.
      expect(plan.outcome, SessionTimeFitOutcome.cannotFit);
      expect(plan.dropExerciseIds, ['e4']);
      expect(plan.projectedMinutes, 39);
    });

    test('cannotFit devuelve el recorte más profundo alcanzable', () {
      final plan = planSessionTimeFit(
        day: _day([
          _slot('e1', minutes: 30),
          _slot('e2', minutes: 30),
          _slot('e3', minutes: 30),
        ]),
        availableMinutes: 10,
      );

      expect(plan.outcome, SessionTimeFitOutcome.cannotFit);
      expect(plan.dropExerciseIds, ['e2', 'e3']);
      expect(plan.projectedMinutes, 30);
    });

    test('un ejercicio ausente esta semana no se cuenta ni se reporta', () {
      final plan = planSessionTimeFit(
        day: _day([
          _slot('e1', minutes: 20),
          _slot('e2', minutes: 20),
          _slot('e3', minutes: 20, activeWeeks: const [1]),
        ]),
        availableMinutes: 25,
      );

      expect(plan.currentMinutes, 40, reason: 'e3 no está en la semana 0');
      expect(plan.outcome, SessionTimeFitOutcome.trimSuggested);
      expect(plan.dropExerciseIds, ['e2'],
          reason: 'e3 nunca estuvo en la sesión de hoy: no se "saca"');
      expect(plan.projectedMinutes, 20);
    });

    test('un ejercicio ausente tampoco traba el recorrido', () {
      final plan = planSessionTimeFit(
        day: _day([
          _slot('e1', minutes: 20),
          _slot('e2', minutes: 20),
          _slot('e3', minutes: 20, activeWeeks: const [1]),
        ]),
        availableMinutes: 25,
        // e3 no se hace hoy, así que aunque estuviera "trabado" no puede
        // frenar el recorte de e2.
        lockedExerciseIds: const {'e3'},
      );

      expect(plan.outcome, SessionTimeFitOutcome.trimSuggested);
      expect(plan.dropExerciseIds, ['e2']);
    });

    test('ignora la duración autorada del día y usa la calculada', () {
      final plan = planSessionTimeFit(
        // El día dice 45 min; los ejercicios suman 60.
        day: _day(
          [
            _slot('e1', minutes: 20),
            _slot('e2', minutes: 20),
            _slot('e3', minutes: 20),
          ],
          estimatedMinutes: 45,
        ),
        availableMinutes: 50,
      );

      expect(plan.currentMinutes, 60,
          reason: 'el 45 autorado no tiene desglose por ejercicio');
      expect(plan.outcome, SessionTimeFitOutcome.trimSuggested);
      expect(plan.projectedMinutes, 40);
      expect(plan.dropExerciseIds, ['e3']);
    });

    test('cada recorte baja el número — nunca lo sube', () {
      final day = _day(
        [
          _slot('e1', minutes: 20),
          _slot('e2', minutes: 20),
          _slot('e3', minutes: 20),
        ],
        estimatedMinutes: 45,
      );
      final plan = planSessionTimeFit(day: day, availableMinutes: 30);

      expect(plan.projectedMinutes, lessThan(plan.currentMinutes!));
    });

    test('un día sin nada medible no ofrece ajuste', () {
      final plan = planSessionTimeFit(
        day: _day(const []),
        availableMinutes: 40,
      );

      expect(plan.outcome, SessionTimeFitOutcome.notMeasurable);
      expect(plan.currentMinutes, isNull);
      expect(plan.projectedMinutes, isNull);
      expect(plan.dropExerciseIds, isEmpty);
    });

    test('respeta la semana activa al estimar y al recortar', () {
      // e3 sólo existe en la semana 1: en la 0 la sesión ya entra.
      final day = _day([
        _slot('e1', minutes: 20),
        _slot('e2', minutes: 20),
        _slot('e3', minutes: 20, activeWeeks: const [1]),
      ]);

      expect(
        planSessionTimeFit(day: day, availableMinutes: 45).outcome,
        SessionTimeFitOutcome.alreadyFits,
      );
      final week1 = planSessionTimeFit(
        day: day,
        availableMinutes: 45,
        week: 1,
      );
      expect(week1.outcome, SessionTimeFitOutcome.trimSuggested);
      expect(week1.dropExerciseIds, ['e3']);
    });
  });
}
