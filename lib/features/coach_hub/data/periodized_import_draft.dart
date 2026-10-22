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
    this.alternatives = const {},
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

  /// PDF: el candidato del extractor cuando pasó el veto pero el fuzzy
  /// sugirió OTRO ejercicio. Se muestra la sugerencia del fuzzy (es
  /// reproducible) y esta queda como alternativa para el picker
  /// (docs/plan-import-pdf.md, «Matcheo»). Nunca se asigna sola. Vacío en el
  /// Excel.
  final Map<ExerciseKey, MatcherExercise> alternatives;

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
      alternatives: {...alternatives}..remove(key),
    );
  }

  /// Como [resolve], pero además asigna [exercise] a los OTROS componentes
  /// todavía sin candidato (ni asignación ni sugerencia) cuyo nombre
  /// normalizado es idéntico al de [key]. Es lo que corresponde al crear un
  /// ejercicio propio: «Press X» repetido en tres días es UN ejercicio.
  /// Nunca toca componentes con otro nombre, aunque se parezcan.
  PeriodizedImportDraft resolveWithSameName(
    ExerciseKey key,
    MatcherExercise exercise,
  ) {
    String? target;
    for (final day in plan.days) {
      for (final row in day.rows) {
        for (final ex in row.exercises) {
          if (exerciseKeyOf(day, row, ex) == key) {
            target = normalize(ex.rawName);
          }
        }
      }
    }
    final next = {...assignments, key: exercise};
    final nextSuggestions = {...suggestions}..remove(key);
    if (target != null && target.isNotEmpty) {
      for (final day in plan.days) {
        for (final row in day.rows) {
          for (final ex in row.exercises) {
            final k = exerciseKeyOf(day, row, ex);
            if (next.containsKey(k) || nextSuggestions.containsKey(k)) continue;
            if (normalize(ex.rawName) == target) next[k] = exercise;
          }
        }
      }
    }
    return PeriodizedImportDraft(
      plan: plan,
      warnings: warnings,
      name: name,
      assignments: next,
      suggestions: nextSuggestions,
      alternatives: {...alternatives}
        ..removeWhere((k, _) => next.containsKey(k)),
    );
  }

  PeriodizedImportDraft withName(String value) => PeriodizedImportDraft(
        plan: plan,
        warnings: warnings,
        name: value,
        assignments: assignments,
        suggestions: suggestions,
        alternatives: alternatives,
      );
}
