import 'exercise_matcher.dart';
import '../domain/periodized_plan.dart';
import 'periodized_routine_mapper.dart';

/// Estado del import en memoria entre la pantalla de subir y la vista previa:
/// el plan leído, los avisos del parser y qué ejercicio del catálogo quedó
/// asignado a cada componente (los automáticos más lo que el PF resolvió).
///
/// Inmutable: resolver un componente devuelve un borrador nuevo.
class PeriodizedImportDraft {
  const PeriodizedImportDraft({
    required this.plan,
    required this.warnings,
    required this.name,
    required this.assignments,
    required this.suggestions,
  });

  /// Arma el borrador a partir del veredicto del matcher: lo exacto o por
  /// alias queda asignado; lo aproximado queda como sugerencia por confirmar.
  factory PeriodizedImportDraft.fromMatch({
    required PeriodizedPlan plan,
    required List<ImportDiagnostic> warnings,
    required String name,
    required PeriodizedMatchResult match,
  }) {
    return PeriodizedImportDraft(
      plan: plan,
      warnings: warnings,
      name: name,
      assignments: match.autoAssigned,
      suggestions: {
        for (final e in match.matches.entries)
          if (e.value.exercise == null && e.value.suggestion != null)
            e.key: e.value.suggestion!,
      },
    );
  }

  final PeriodizedPlan plan;

  /// Avisos del parser (numeración salteada, ejercicio sin reps…). Nunca
  /// bloquean.
  final List<ImportDiagnostic> warnings;

  /// Nombre de la rutina; el PF lo puede cambiar en la vista previa.
  final String name;

  /// Ejercicio FINAL de cada componente ya resuelto.
  final Map<ExerciseKey, MatcherExercise> assignments;

  /// Sugerencias aproximadas del matcher (#1455) que el PF todavía no
  /// confirmó. Un componente con sugerencia NO está asignado.
  final Map<ExerciseKey, MatcherExercise> suggestions;

  bool isResolved(ExerciseKey key) => assignments.containsKey(key);

  /// Componentes que bloquean la asignación: con sugerencia pendiente o sin
  /// candidato.
  List<ExerciseKey> get unresolved => [
        for (final day in plan.days)
          for (final row in day.rows)
            for (final ex in row.exercises)
              if (!isResolved(exerciseKeyOf(day, row, ex)))
                exerciseKeyOf(day, row, ex),
      ];

  int get pendingSuggestions =>
      unresolved.where(suggestions.containsKey).length;

  int get withoutSuggestion =>
      unresolved.where((k) => !suggestions.containsKey(k)).length;

  /// Asigna [exercise] al componente [key] y descarta su sugerencia.
  PeriodizedImportDraft resolve(ExerciseKey key, MatcherExercise exercise) {
    return PeriodizedImportDraft(
      plan: plan,
      warnings: warnings,
      name: name,
      assignments: {...assignments, key: exercise},
      suggestions: {...suggestions}..remove(key),
    );
  }

  PeriodizedImportDraft withName(String value) => PeriodizedImportDraft(
        plan: plan,
        warnings: warnings,
        name: value,
        assignments: assignments,
        suggestions: suggestions,
      );
}
