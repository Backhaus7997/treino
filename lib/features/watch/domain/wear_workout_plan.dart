import '../../workout/domain/routine.dart';
import '../../workout/domain/set_spec.dart';

/// Un ejercicio del entreno, con todo lo que el reloj necesita para ejecutarlo.
///
/// Es lo que la vista previa de HOY **no** trae: aquélla sólo muestra nombre y
/// cuántas series. Para entrenar hacen falta además el `exerciseId` —sin él no
/// se puede escribir la serie— y el descanso.
class WearPlannedExercise {
  const WearPlannedExercise({
    required this.exerciseId,
    required this.exerciseName,
    required this.sets,
    required this.restSeconds,
    this.supersetGroup,
  });

  /// Sin esto no hay escritura posible: es la mitad de la identidad de la serie.
  final String exerciseId;

  /// Denormalizado en la rutina (ADR-2), así que el reloj no necesita el
  /// catálogo de ejercicios.
  final String exerciseName;

  /// Ya resueltas para la semana de la sesión. Ver [wearWorkoutPlanFrom].
  final List<SetSpec> sets;

  /// Descanso del EJERCICIO, no de la serie.
  ///
  /// Vive en `RoutineSlot.restSeconds`. El HANDOFF §6.3 dice que sale del
  /// `SetSpec` y es **falso**: `SetSpec` tiene seis campos y ninguno es
  /// descanso.
  final int restSeconds;

  /// A qué superserie pertenece, o null si es un ejercicio suelto.
  ///
  /// Sale tal cual de `RoutineSlot.supersetGroup`. Sin esto el reloj no podía
  /// distinguir una superserie A/B/C de tres ejercicios independientes, y por
  /// eso avanzaba A1→A2→A3 en vez de 1a→1b→1c. Ver `wearCurrentExerciseIndex`.
  final int? supersetGroup;
}

/// El entreno completo que el reloj está por ejecutar, o ejecutando.
class WearWorkoutPlan {
  const WearWorkoutPlan({
    required this.routineId,
    required this.routineName,
    required this.dayName,
    required this.dayNumber,
    required this.weekNumber,
    required this.exercises,
  });

  final String routineId;
  final String routineName;
  final String dayName;

  /// 1-based, igual que `RoutineDay.dayNumber`.
  final int dayNumber;

  /// 0-based, igual que `Session.weekNumber`.
  final int weekNumber;

  final List<WearPlannedExercise> exercises;

  /// Cuántas series pide el plan por ejercicio, en orden.
  ///
  /// Es una de las entradas de `wearCurrentExerciseIndex`.
  List<int> get plannedSets => [for (final e in exercises) e.sets.length];

  /// La superserie de cada ejercicio, en el MISMO orden que [plannedSets].
  ///
  /// La otra entrada del cursor. Va alineada por posición y no por id porque el
  /// mismo ejercicio puede aparecer dos veces en un día.
  List<int?> get supersetGroups => [for (final e in exercises) e.supersetGroup];
}

/// Resuelve el plan del día [dayNumber] en la semana [weekNumber].
///
/// ## La posición la manda quien llama, y eso NO es un detalle
///
/// El día se busca por [dayNumber] EXPLÍCITO, nunca «el que tocaría hoy». Para
/// una sesión que ya existe, la posición sale de la SESIÓN.
///
/// Ese fue el bug más caro del lado Apple (HANDOFF §4.4): el reloj adoptaba el
/// entreno abierto en el teléfono pero calculaba el día con `nextPlanPosition`,
/// así que cada dispositivo miraba un día distinto del plan. Se veía como «dejó
/// de sincronizar» —los datos cruzaban perfecto— y las series se escribían con
/// los ejercicios del día equivocado.
///
/// Las dos reglas de periodización son las mismas que ya aplica la vista previa
/// de HOY, y están bajo el contrato de `conformance/set_resolution.json`:
/// [RoutineSlot.isPresentInWeek] filtra los ejercicios que esta semana no
/// existen, y [RoutineSlot.effectiveSetsForWeek] da las series de ESA semana
/// —incluida la semana autorizada vacía de una descarga—.
///
/// Devuelve null si la rutina no tiene ese día: es un dato inconsistente y
/// arrancar un entreno vacío sería peor que no arrancarlo.
WearWorkoutPlan? wearWorkoutPlanFrom({
  required Routine routine,
  required int dayNumber,
  required int weekNumber,
}) {
  for (final day in routine.days) {
    if (day.dayNumber != dayNumber) continue;

    // Se clampea igual que `SessionNotifier`: un `weekNumber` fuera de rango
    // —doc viejo, o una rutina a la que le sacaron semanas— indexaría
    // `weeklySets` fuera de rango. `effectiveSetsForWeek` ya es defensivo, pero
    // clampear acá deja el plan entero coherente en vez de mezclar semanas.
    final maxWeek = routine.numWeeks > 1 ? routine.numWeeks - 1 : 0;
    final week = weekNumber.clamp(0, maxWeek);

    return WearWorkoutPlan(
      routineId: routine.id,
      routineName: routine.name,
      dayName: day.name,
      dayNumber: dayNumber,
      weekNumber: week,
      exercises: [
        for (final slot in day.slots)
          if (slot.isPresentInWeek(week))
            WearPlannedExercise(
              exerciseId: slot.exerciseId,
              exerciseName: slot.exerciseName,
              sets: slot.effectiveSetsForWeek(week),
              restSeconds: slot.restSeconds,
              supersetGroup: slot.supersetGroup,
            ),
      ],
    );
  }

  return null;
}
