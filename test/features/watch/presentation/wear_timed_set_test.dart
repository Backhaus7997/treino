import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/watch/presentation/wear/wear_workout_view_model.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

void main() {
  WearWorkoutSnapshot snapshot({
    required List<SetSpec> sets,
    Set<int> marcadas = const {},
  }) =>
      WearWorkoutSnapshot(
        exerciseId: 'plancha',
        exerciseName: 'Plancha',
        exerciseIndex: 0,
        exerciseCount: 1,
        dayName: 'Core',
        sets: sets,
        loggedSetNumbers: marcadas,
        restSeconds: 60,
        isFullyCompleted: false,
      );

  group('distinguir una serie que se AGUANTA de una que se MARCA', () {
    test('una serie por tiempo declara su duración', () {
      final s = snapshot(sets: const [SetSpec(durationSeconds: 45)]);

      expect(s.durationSecondsOf(1), 45);
      expect(s.nextSetIsTimed, isTrue);
    });

    test('una serie de repeticiones no tiene duración', () {
      // El default de `durationSeconds` es null, y un ejercicio de reps tiene
      // que caer en el camino de marcar directo, no en el temporizador.
      final s = snapshot(sets: const [SetSpec(reps: 10)]);

      expect(s.durationSecondsOf(1), 0);
      expect(s.nextSetIsTimed, isFalse);
    });

    test('una duración en CERO no cuenta como serie por tiempo', () {
      // Pasa con datos viejos o mal cargados. Tratarla como temporizada abriría
      // una pantalla que nace vencida.
      final s = snapshot(sets: const [SetSpec(durationSeconds: 0)]);

      expect(s.durationSecondsOf(1), 0);
      expect(s.nextSetIsTimed, isFalse);
    });

    test('un número de serie fuera de rango devuelve 0 y no revienta', () {
      final s = snapshot(sets: const [SetSpec(durationSeconds: 45)]);

      expect(s.durationSecondsOf(0), 0);
      expect(s.durationSecondsOf(2), 0);
      expect(s.durationSecondsOf(-1), 0);
    });

    test('mira la PRÓXIMA serie, no la primera del plan', () {
      // Un ejercicio puede mezclar: dos series por tiempo y una de reps. Si
      // `nextSetIsTimed` mirara siempre la serie 1, después de marcar la
      // primera abriría el temporizador para una serie de repeticiones.
      final s = snapshot(
        sets: const [SetSpec(durationSeconds: 45), SetSpec(reps: 10)],
        marcadas: {1},
      );

      expect(s.nextSetNumber, 2);
      expect(s.nextSetIsTimed, isFalse);
    });

    test('con todas las series marcadas no hay próxima ni temporizador', () {
      final s = snapshot(
        sets: const [SetSpec(durationSeconds: 45)],
        marcadas: {1},
      );

      expect(s.nextSetNumber, isNull);
      expect(s.nextSetIsTimed, isFalse);
    });
  });
}
