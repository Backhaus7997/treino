// Tests del builder puro del WorkoutSnapshot (share-composer PR1):
// agrupamiento por exerciseName preservando orden, truncado a
// kMaxSnapshotExercises, serialización de ejes por RadarAxis.name y
// roundtrip JSON (el snapshot viaja embebido en el doc del post y el
// render del feed lo rehidrata con fromJson).

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/domain/workout_snapshot.dart';
import 'package:treino/features/insights/domain/radar_axis.dart';
import 'package:treino/features/workout/domain/set_log.dart';

SetLog _log({
  required String exerciseName,
  String exerciseId = 'e1',
  int setNumber = 1,
  int reps = 10,
  double weightKg = 50,
}) =>
    SetLog(
      id: '$exerciseName-$setNumber',
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      setNumber: setNumber,
      reps: reps,
      weightKg: weightKg,
      completedAt: DateTime.utc(2026, 7, 28, 10, 0),
    );

void main() {
  group('buildWorkoutSnapshot', () {
    test('agrupa por exerciseName preservando orden de primera aparición', () {
      final snapshot = buildWorkoutSnapshot(
        setLogs: [
          _log(exerciseName: 'Press banca', setNumber: 1),
          _log(exerciseName: 'Press banca', setNumber: 2),
          _log(exerciseName: 'Sentadilla', setNumber: 1, weightKg: 80),
          // Set tardío de un ejercicio ya visto — se agrupa con el primero,
          // no crea un grupo nuevo (mismo fold que SessionDetailScreen).
          _log(exerciseName: 'Press banca', setNumber: 3),
        ],
        setsByAxis: const {RadarAxis.chest: 3, RadarAxis.legs: 1},
        volumeKgByAxis: const {RadarAxis.chest: 1500, RadarAxis.legs: 800},
      );

      expect(snapshot.exercises, hasLength(2));
      expect(snapshot.exercises[0].exerciseName, 'Press banca');
      expect(snapshot.exercises[0].sets, hasLength(3));
      expect(
        snapshot.exercises[0].sets.map((s) => s.setNumber),
        [1, 2, 3],
      );
      expect(snapshot.exercises[1].exerciseName, 'Sentadilla');
      expect(snapshot.exercises[1].sets.single.weightKg, 80);
      expect(snapshot.setsByAxis, {'chest': 3, 'legs': 1});
      expect(snapshot.volumeKgByAxis, {'chest': 1500, 'legs': 800});
      expect(snapshot.truncated, isFalse);
    });

    test('sesión vacía → snapshot sin ejercicios ni truncado', () {
      final snapshot = buildWorkoutSnapshot(setLogs: const []);

      expect(snapshot.exercises, isEmpty);
      expect(snapshot.setsByAxis, isEmpty);
      expect(snapshot.volumeKgByAxis, isEmpty);
      expect(snapshot.truncated, isFalse);
    });

    test(
        'más de $kMaxSnapshotExercises ejercicios → trunca a los primeros '
        'y marca truncated', () {
      final snapshot = buildWorkoutSnapshot(
        setLogs: [
          for (var i = 0; i < kMaxSnapshotExercises + 5; i++)
            _log(exerciseName: 'Ejercicio $i', exerciseId: 'e$i'),
        ],
      );

      expect(snapshot.exercises, hasLength(kMaxSnapshotExercises));
      expect(snapshot.exercises.first.exerciseName, 'Ejercicio 0');
      expect(
        snapshot.exercises.last.exerciseName,
        'Ejercicio ${kMaxSnapshotExercises - 1}',
      );
      expect(snapshot.truncated, isTrue);
    });

    test('exactamente $kMaxSnapshotExercises ejercicios NO marca truncated',
        () {
      final snapshot = buildWorkoutSnapshot(
        setLogs: [
          for (var i = 0; i < kMaxSnapshotExercises; i++)
            _log(exerciseName: 'Ejercicio $i', exerciseId: 'e$i'),
        ],
      );

      expect(snapshot.exercises, hasLength(kMaxSnapshotExercises));
      expect(snapshot.truncated, isFalse);
    });
  });

  group('WorkoutSnapshot JSON', () {
    test('roundtrip toJson → fromJson rehidrata sets como SetLog', () {
      final original = buildWorkoutSnapshot(
        setLogs: [
          _log(exerciseName: 'Press banca', setNumber: 1, reps: 8),
          _log(exerciseName: 'Press banca', setNumber: 2, reps: 6),
        ],
        setsByAxis: const {RadarAxis.chest: 2},
        volumeKgByAxis: const {RadarAxis.chest: 700},
      );

      final rehydrated = WorkoutSnapshot.fromJson(original.toJson());

      expect(rehydrated, equals(original));
      expect(rehydrated.exercises.single.sets.first, isA<SetLog>());
      expect(rehydrated.exercises.single.sets.first.reps, 8);
    });

    test('mapas de ejes ausentes en el JSON caen a defaults vacíos', () {
      // Un doc crafteado a mano vía SDK puede omitir los mapas — las rules
      // solo validan la capa externa. El parse no debe explotar.
      final snapshot = WorkoutSnapshot.fromJson(const {
        'exercises': <Object?>[],
      });

      expect(snapshot.exercises, isEmpty);
      expect(snapshot.setsByAxis, isEmpty);
      expect(snapshot.volumeKgByAxis, isEmpty);
      expect(snapshot.truncated, isFalse);
    });
  });
}
