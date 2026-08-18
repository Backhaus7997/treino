import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/watch/domain/wear_workout_plan.dart';
import 'package:treino/features/watch/domain/wear_workout_session.dart';
import 'package:treino/features/watch/presentation/wear/wear_workout_view_model.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

WearPlannedExercise _ej(String id, int series, {int rest = 60}) =>
    WearPlannedExercise(
      exerciseId: id,
      exerciseName: id,
      sets: [for (var i = 0; i < series; i++) const SetSpec(reps: 10)],
      restSeconds: rest,
    );

WearWorkoutPlan _plan(List<WearPlannedExercise> ejercicios) => WearWorkoutPlan(
      routineId: 'r1',
      routineName: 'Fuerza Base',
      dayName: 'Empuje',
      dayNumber: 1,
      weekNumber: 0,
      exercises: ejercicios,
    );

WearWorkoutSession _sesion(
  WearWorkoutPlan plan, {
  List<WearLoggedSet> logged = const [],
  Set<String> pending = const {},
}) =>
    WearWorkoutSession(
      sessionId: 's1',
      startedAt: DateTime.utc(2026, 8, 18, 10),
      plan: plan,
      logged: logged,
      pending: pending,
    );

List<WearLoggedSet> _marcadas(String id, int hasta,
        {int reps = 10, double kg = 100}) =>
    [
      for (var n = 1; n <= hasta; n++)
        WearLoggedSet(
          docId: '${id}__$n',
          exerciseId: id,
          setNumber: n,
          reps: reps,
          weightKg: kg,
        ),
    ];

void main() {
  group('el cursor — el síntoma que reportó el dueño', () {
    test('marcadas las 4 series del primero, pasa al SEGUNDO', () {
      // "marco las 4 del primer ejercicio y se queda ahí, no pasa al
      // siguiente". Convertido en test.
      final s = _sesion(
        _plan([_ej('press', 4), _ej('remo', 3), _ej('curl', 3)]),
        logged: _marcadas('press', 4),
      );

      expect(s.currentExerciseIndex, 1);
      expect(s.isFullyCompleted, isFalse);
    });

    test('dos ejercicios completados de una: salta los DOS', () {
      final s = _sesion(
        _plan([_ej('press', 4), _ej('remo', 3), _ej('curl', 3)]),
        logged: [..._marcadas('press', 4), ..._marcadas('remo', 3)],
      );

      expect(s.currentExerciseIndex, 2);
    });

    test('si el teléfono borra una serie, el cursor VUELVE', () {
      // Con un delta esto era inexpresable, y es exactamente lo que hacía que
      // el reloj quedara clavado.
      final completo = _sesion(
        _plan([_ej('press', 4), _ej('remo', 3)]),
        logged: [..._marcadas('press', 4), ..._marcadas('remo', 3)],
      );
      expect(completo.currentExerciseIndex, 1);

      final borrada = _sesion(
        _plan([_ej('press', 4), _ej('remo', 3)]),
        logged: [..._marcadas('press', 3), ..._marcadas('remo', 3)],
      );
      expect(borrada.currentExerciseIndex, 0);
    });

    test('con todo completo se queda en el último, no se va de rango', () {
      final s = _sesion(
        _plan([_ej('press', 2), _ej('remo', 2)]),
        logged: [..._marcadas('press', 2), ..._marcadas('remo', 2)],
      );

      expect(s.currentExerciseIndex, 1);
      expect(s.isFullyCompleted, isTrue);
    });
  });

  group('identidades, no documentos', () {
    test('dos documentos de la MISMA serie cuentan una sola vez', () {
      // Si el teléfono y el reloj dejaron dos docs de la misma serie lógica,
      // contarlos sobrecontaría y el cursor saltearía un ejercicio entero.
      final s = _sesion(
        _plan([_ej('press', 3), _ej('remo', 3)]),
        logged: [
          ..._marcadas('press', 2),
          // El duplicado: misma identidad lógica, otro documento.
          // Otro documento, misma identidad lógica.
          const WearLoggedSet(
              docId: 'auto-xyz',
              exerciseId: 'press',
              setNumber: 2,
              reps: 8,
              weightKg: 90),
        ],
      );

      expect(s.loggedSets, [2, 0]);
      expect(s.currentExerciseIndex, 0, reason: 'al press le falta la 3');
    });

    test('una escritura en vuelo ya cuenta como marcada', () {
      final s = _sesion(
        _plan([_ej('press', 2), _ej('remo', 2)]),
        logged: _marcadas('press', 1),
        pending: {'press__2'},
      );

      expect(s.loggedSets, [2, 0]);
      expect(s.currentExerciseIndex, 1);
    });
  });

  group('isFullyCompleted', () {
    test('un plan sin ejercicios NO está completo', () {
      expect(_sesion(_plan([])).isFullyCompleted, isFalse);
    });

    test('un plan con cero series planificadas tampoco', () {
      // Sin este guard un entreno vacío nacería "completo" y contaría para la
      // racha. Mismo agujero que cierra SessionState del lado del teléfono.
      final s = _sesion(_plan([_ej('press', 0), _ej('remo', 0)]));

      expect(s.isFullyCompleted, isFalse);
    });

    test('un ejercicio de descarga vacío no impide completar el entreno', () {
      // La semana autorizada como vacía deja un slot en cero: cuenta como
      // hecho, así el atleta puede terminar.
      final s = _sesion(
        _plan([_ej('press', 2), _ej('descarga', 0)]),
        logged: _marcadas('press', 2),
      );

      expect(s.isFullyCompleted, isTrue);
    });
  });

  test('el volumen sale de las series REALES, no de las que están en vuelo',
      () {
    final s = _sesion(
      _plan([_ej('press', 3)]),
      logged: _marcadas('press', 2, reps: 10, kg: 50),
      pending: {'press__3'},
    );

    expect(s.totalVolumeKg, 1000.0);
  });

  group('la proyección al snapshot', () {
    test('proyecta el ejercicio ACTUAL, con sus propios datos', () {
      final s = _sesion(
        _plan([_ej('press', 2, rest: 120), _ej('remo', 3, rest: 45)]),
        logged: _marcadas('press', 2),
      );

      final snap = wearSnapshotFrom(s)!;

      expect(snap.exerciseId, 'remo');
      expect(snap.exerciseIndex, 1);
      expect(snap.exerciseCount, 2);
      // El descanso es el del ejercicio actual, no el del anterior.
      expect(snap.restSeconds, 45);
      expect(snap.sets.length, 3);
      expect(snap.loggedSetNumbers, isEmpty);
    });

    test('las series marcadas son SOLO las de este ejercicio', () {
      final s = _sesion(
        _plan([_ej('press', 3), _ej('remo', 3)]),
        logged: [..._marcadas('press', 3), ..._marcadas('remo', 1)],
      );

      final snap = wearSnapshotFrom(s)!;

      expect(snap.exerciseId, 'remo');
      expect(snap.loggedSetNumbers, {1});
      expect(snap.nextSetNumber, 2);
    });

    test('lleva isFullyCompleted del ENTRENO, no del ejercicio', () {
      final s = _sesion(
        _plan([_ej('press', 1), _ej('remo', 1)]),
        logged: _marcadas('press', 1),
      );

      final snap = wearSnapshotFrom(s)!;

      // El ejercicio actual (remo) no tiene nada marcado, pero lo que importa
      // para Terminar es el entreno entero.
      expect(snap.isFullyCompleted, isFalse);
    });

    test('un plan sin ejercicios no proyecta nada', () {
      // Puede pasar: una semana de descarga puede dejar el día sin ejercicios
      // presentes.
      expect(wearSnapshotFrom(_sesion(_plan([]))), isNull);
    });
  });
}
