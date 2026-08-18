import '../../../workout/domain/set_spec.dart';
import '../../domain/wear_workout_session.dart';

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
    required this.exerciseId,
    required this.exerciseName,
    required this.exerciseIndex,
    required this.exerciseCount,
    required this.dayName,
    required this.sets,
    required this.loggedSetNumbers,
    required this.restSeconds,
    required this.isFullyCompleted,
    this.pendingUploadCount = 0,
  });

  /// Mitad de la identidad de cada serie de este ejercicio.
  ///
  /// Lo lleva el snapshot —y no lo resuelve quien marca— para cerrar una
  /// carrera real: entre que la fila se dibuja y el atleta la toca puede llegar
  /// un snapshot del teléfono que mueva el cursor, y la serie terminaría
  /// escrita en OTRO ejercicio.
  final String exerciseId;

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

  /// Descanso de ESTE ejercicio, en segundos.
  ///
  /// Sale de `RoutineSlot.restSeconds`. Va en el snapshot y no se busca al
  /// marcar por el mismo motivo que [exerciseId]: la última serie de un
  /// ejercicio arranca el descanso y ACTO SEGUIDO el cursor avanza, así que
  /// leerlo después daría el descanso del ejercicio siguiente.
  final int restSeconds;

  /// Si están todas las series de TODOS los ejercicios del entreno.
  ///
  /// Es del ENTRENO, no de este ejercicio: es la condición de «Terminar», y por
  /// eso un snapshot de un solo ejercicio nunca pudo calcularla.
  final bool isFullyCompleted;

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
}

/// Proyecta el entreno completo a lo que la pantalla dibuja: el ejercicio
/// actual.
///
/// ## Por qué el snapshot se DERIVA en vez de crecer
///
/// La tentación era hacer `WearWorkoutSnapshot` multi-ejercicio. No se hizo, y
/// por cuatro razones:
///
/// 1. Los widgets ya leen exactamente esta proyección. Crecer el snapshot los
///    obligaría a todos a escribir `snapshot.exercises[snapshot.index]...`.
/// 2. Derivar deja la regla pura y testeable sin bombear widgets.
/// 3. **«Siempre absoluto» sale gratis**: la proyección se recalcula del modelo
///    entero en cada build, así que no hay dónde meter un delta. Ése es el
///    punto: `withLogged` existía justamente porque el snapshot era el estado.
/// 4. Simetría con watchOS, que guarda `workout` + `currentExerciseIndex` y la
///    vista lee `workout.currentExercise`. Es el mismo corte.
///
/// Devuelve null si el plan no tiene ejercicios. No es defensivo de más: una
/// semana de descarga puede dejar un día entero sin ejercicios presentes, y
/// entonces no hay ejercicio actual que dibujar.
WearWorkoutSnapshot? wearSnapshotFrom(WearWorkoutSession session) {
  final ejercicios = session.plan.exercises;
  if (ejercicios.isEmpty) return null;

  final indice = session.currentExerciseIndex;
  final actual = ejercicios[indice];
  final marcadas = session.identities;

  return WearWorkoutSnapshot(
    exerciseId: actual.exerciseId,
    exerciseName: actual.exerciseName,
    exerciseIndex: indice,
    exerciseCount: ejercicios.length,
    dayName: session.plan.dayName,
    sets: actual.sets,
    // Sólo las de ESTE ejercicio, y por identidad lógica.
    loggedSetNumbers: {
      for (var n = 1; n <= actual.sets.length; n++)
        if (marcadas.contains('${actual.exerciseId}__$n')) n,
    },
    restSeconds: actual.restSeconds,
    isFullyCompleted: session.isFullyCompleted,
    pendingUploadCount: session.pending.length,
  );
}
