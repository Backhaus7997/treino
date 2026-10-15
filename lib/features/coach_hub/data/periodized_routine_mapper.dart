import '../../profile/domain/experience_level.dart';
import '../../workout/domain/routine.dart';
import '../../workout/domain/routine_day.dart';
import '../../workout/domain/routine_slot.dart';
import '../../workout/domain/set_enums.dart';
import '../../workout/domain/set_spec.dart';
import '../domain/periodized_plan.dart';
import 'exercise_matcher.dart';

/// Veredictos del matcher (#1455) para cada componente del plan.
class PeriodizedMatchResult {
  PeriodizedMatchResult(this.matches);

  /// Un veredicto por componente; cada ejercicio de una superserie va por
  /// separado.
  final Map<ExerciseKey, ExerciseNameMatch> matches;

  /// Lo que se asigna solo: coincidencia exacta o por alias.
  Map<ExerciseKey, MatcherExercise> get autoAssigned => {
        for (final e in matches.entries)
          if (e.value.exercise != null) e.key: e.value.exercise!,
      };

  /// Componentes que bloquean la asignación hasta resolverse: con sugerencia
  /// por confirmar o sin candidato.
  List<ExerciseKey> get needsReview => [
        for (final e in matches.entries)
          if (e.value.exercise == null) e.key,
      ];
}

/// Pasa CADA componente de CADA renglón por el matcher, por separado.
PeriodizedMatchResult matchPeriodizedPlan(
  PeriodizedPlan plan,
  List<MatcherExercise> catalog,
) {
  final matcher = ExerciseNameMatcher(catalog);
  final matches = <ExerciseKey, ExerciseNameMatch>{};
  for (final day in plan.days) {
    for (final row in day.rows) {
      for (final ex in row.exercises) {
        matches[exerciseKeyOf(day, row, ex)] = matcher.match(ex.rawName);
      }
    }
  }
  return PeriodizedMatchResult(matches);
}

ExerciseKey exerciseKeyOf(
  PeriodizedDay day,
  PeriodizedRow row,
  PeriodizedExercise ex,
) =>
    (dayNumber: day.dayNumber, row: row.excelRow, component: ex.component);

/// Claves del plan que todavía no tienen ejercicio asignado.
List<ExerciseKey> unresolvedKeys(
  PeriodizedPlan plan,
  Map<ExerciseKey, MatcherExercise> assignments,
) =>
    [
      for (final day in plan.days)
        for (final row in day.rows)
          for (final ex in row.exercises)
            if (!assignments.containsKey(exerciseKeyOf(day, row, ex)))
              exerciseKeyOf(day, row, ex),
    ];

/// Arma la `Routine` periodizada. [assignments] trae el ejercicio FINAL de cada
/// componente (los automáticos del matcher más lo que el PF confirmó o asignó
/// a mano); si falta alguno, tira [ArgumentError]: asignar con un ejercicio sin
/// resolver está bloqueado por la política de #1455.
///
/// La `Routine` sale con los defaults de procedencia (`source`, `assignedTo`…):
/// quien la persiste los completa con `copyWith`.
Routine mapPeriodizedPlanToRoutine(
  PeriodizedPlan plan,
  Map<ExerciseKey, MatcherExercise> assignments, {
  required String routineId,
  required String routineName,
  required ExperienceLevel level,
}) {
  final missing = unresolvedKeys(plan, assignments);
  if (missing.isNotEmpty) {
    throw ArgumentError(
      'Hay ${missing.length} ejercicio(s) sin asignar: $missing',
    );
  }

  // Los bloques DÍA sin ningún renglón cargado (la plantilla trae 7) no son
  // días de la rutina: se descartan.
  final days = [
    for (final day in plan.days)
      if (day.rows.isNotEmpty)
        _mapDay(day, assignments, numWeeks: plan.numWeeks),
  ];

  return Routine(
    id: routineId,
    name: routineName,
    level: level,
    days: days,
    numWeeks: plan.numWeeks,
  );
}

RoutineDay _mapDay(
  PeriodizedDay day,
  Map<ExerciseKey, MatcherExercise> assignments, {
  required int numWeeks,
}) {
  final slots = <RoutineSlot>[];
  // Ids de superserie por día, desde 1, uno por renglón: igual que el editor.
  var nextGroup = 1;
  for (final row in day.rows) {
    final int? group = row.isSuperset ? nextGroup++ : null;
    for (var i = 0; i < row.exercises.length; i++) {
      final ex = row.exercises[i];
      final isLast = i == row.exercises.length - 1;
      slots.add(_mapSlot(
        ex,
        assignments[exerciseKeyOf(day, row, ex)]!,
        numWeeks: numWeeks,
        supersetGroup: group,
        // El descanso es de la superserie entera: va en el último slot.
        restSeconds: isLast ? row.restSeconds : 0,
      ));
    }
  }
  return RoutineDay(
    dayNumber: day.dayNumber,
    name: 'Día ${day.dayNumber}',
    slots: slots,
  );
}

/// Modo del slot: distancia si alguna serie lleva metros, duración si alguna
/// lleva segundos, reps en el resto (misma precedencia que
/// `RoutineSlot.effectiveExerciseMode`).
ExerciseMode _modeOf(List<List<SetSpec>> weeks) {
  bool any(bool Function(SetSpec) f) => weeks.any((w) => w.any(f));
  if (any((s) => (s.distanceMeters ?? 0) > 0)) return ExerciseMode.distance;
  if (any((s) => (s.durationSeconds ?? 0) > 0)) return ExerciseMode.duration;
  return ExerciseMode.reps;
}

/// Deja en la serie sólo los campos del modo del slot (el modo es por slot,
/// no por semana), como `toSpec` del editor web.
SetSpec _coerce(SetSpec s, ExerciseMode mode) => switch (mode) {
      ExerciseMode.reps => SetSpec(type: s.type, reps: s.reps),
      ExerciseMode.duration =>
        SetSpec(type: s.type, durationSeconds: s.durationSeconds),
      ExerciseMode.distance =>
        SetSpec(type: s.type, distanceMeters: s.distanceMeters),
    };

/// Una semana tiene prescripción si alguna serie trae reps, duración,
/// distancia o un tipo que ya dice algo (fallo, drop). La celda vacía deja una
/// serie normal/calentamiento sin ningún valor.
bool _weekHasPrescription(List<SetSpec> week) => week.any((s) =>
    s.reps != null ||
    s.durationSeconds != null ||
    s.distanceMeters != null ||
    s.weightKg != null ||
    s.type == SetType.failure ||
    s.type == SetType.drop);

RoutineSlot _mapSlot(
  PeriodizedExercise ex,
  MatcherExercise exercise, {
  required int numWeeks,
  required int? supersetGroup,
  required int restSeconds,
}) {
  final mode = _modeOf(ex.weeks);
  final weeks = [
    for (final w in ex.weeks) [for (final s in w) _coerce(s, mode)],
  ];
  // Campos legacy = la primera semana CON prescripción (normalmente SEMANA 1,
  // como el editor): los consumidores que no conocen `weeklySets` leen sólo
  // estos campos, y una SEMANA 1 vacía los dejaría sin reps ni duración.
  // `weeklySets` conserva todas las semanas tal cual. Sin datos en ninguna
  // semana, queda SEMANA 1.
  final week0 =
      weeks.firstWhere(_weekHasPrescription, orElse: () => weeks.first);

  var targetRepsMin = 0;
  var targetRepsMax = 0;
  var targetReps = const <int>[];
  int? durationSeconds;
  switch (mode) {
    case ExerciseMode.duration:
      durationSeconds = week0.isEmpty ? null : week0.first.durationSeconds;
    case ExerciseMode.distance:
      break;
    case ExerciseMode.reps:
      final reps = week0.map((s) => s.reps ?? 0).toList();
      targetReps = reps;
      if (reps.isNotEmpty) {
        targetRepsMin = reps.reduce((a, b) => a < b ? a : b);
        targetRepsMax = reps.reduce((a, b) => a > b ? a : b);
      }
  }

  return RoutineSlot(
    exerciseId: exercise.id,
    exerciseName: exercise.name,
    muscleGroup: exercise.muscleGroup ?? '',
    targetSets: week0.length,
    targetRepsMin: targetRepsMin,
    targetRepsMax: targetRepsMax,
    restSeconds: restSeconds,
    supersetGroup: supersetGroup,
    notes: ex.note,
    targetReps: targetReps,
    durationSeconds: durationSeconds,
    exerciseMode: mode,
    sets: week0,
    // Igual que el editor: un plan de UNA semana deja weeklySets vacío.
    weeklySets: numWeeks > 1 ? weeks : const [],
    // Vacío = presente en todas las semanas: ningún slot falta en una semana.
    activeWeeks: const [],
  );
}
