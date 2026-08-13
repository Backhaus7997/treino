import '../../../workout/domain/set_spec.dart';

/// Lo que la pantalla de entreno del reloj necesita saber, y nada más.
///
/// Espeja lo que `WorkoutView.swift` lee de `WorkoutCoordinator`: el ejercicio
/// actual, su posición dentro del entreno, y el estado de cada serie.
///
/// Es un tipo de PRESENTACIÓN a propósito, sin Firestore ni providers adentro:
/// así la pantalla se puede armar y mirar antes de que exista la carga real de
/// la sesión, y después se testea sin levantar red.
class WearWorkoutSnapshot {
  const WearWorkoutSnapshot({
    required this.exerciseName,
    required this.exerciseIndex,
    required this.exerciseCount,
    required this.dayName,
    required this.sets,
    required this.loggedSetNumbers,
    this.pendingUploadCount = 0,
  });

  final String exerciseName;

  /// 0-based, como `currentExerciseIndex` en Swift. Se muestra +1.
  final int exerciseIndex;
  final int exerciseCount;
  final String dayName;

  final List<SetSpec> sets;

  /// Números de serie (1-based) ya marcados.
  final Set<int> loggedSetNumbers;

  /// Series marcadas que todavía no subieron. En watchOS se muestran en naranja.
  final int pendingUploadCount;

  bool isLogged(int setNumber) => loggedSetNumbers.contains(setNumber);

  /// La ÚNICA serie que se puede marcar es la primera sin marcar.
  ///
  /// Regla copiada literal de watchOS, y la razón está documentada allá: sin
  /// esto se podía tocar la 3 sin haber hecho la 2, y quedaba un hueco. El
  /// historial mostraba series salteadas, el conteo de completado mentía, y en
  /// el teléfono —que sí ordena— el ejercicio se veía inconsistente. En la
  /// muñeca es fácil de hacer sin querer, porque los círculos están a
  /// milímetros.
  int? get nextSetNumber {
    for (var n = 1; n <= sets.length; n++) {
      if (!isLogged(n)) return n;
    }
    return null;
  }

  /// Si están todas las series de este ejercicio.
  ///
  /// OJO: en watchOS "Terminar" exige TODAS las series de TODOS los ejercicios
  /// (`workout.isFullyCompleted`). Acá sólo se sabe del ejercicio actual hasta
  /// que se cablee la sesión completa, así que esto NO alcanza para habilitar
  /// el botón de terminar.
  bool get isCurrentExerciseComplete => nextSetNumber == null;
}
