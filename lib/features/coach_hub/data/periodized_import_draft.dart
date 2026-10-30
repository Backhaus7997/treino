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
    this.aliasKeys = const {},
    this.athleteId,
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

  /// Componentes cuya asignación FINAL la eligió el PF sobre el catálogo
  /// (sugerencia confirmada, alternativa o el picker): son los que enseñan un
  /// alias al asignar el plan. Quedan afuera los automáticos (exacto o por
  /// alias: no hay nada que aprender), los propios del PF y los sin match.
  /// Se recalcula con cada resolución, así un «Cambiar» deja sólo el último.
  final Set<ExerciseKey> aliasKeys;

  /// Los alias a registrar después de asignar: `rawName` del componente →
  /// ejercicio asignado, sin pares repetidos, en el orden del plan.
  List<({String exerciseId, String alias})> get aliasesToRegister {
    final seen = <(String, String)>{};
    final out = <({String exerciseId, String alias})>[];
    for (final day in plan.days) {
      for (final row in day.rows) {
        for (final ex in row.exercises) {
          final key = exerciseKeyOf(day, row, ex);
          final assigned = assignments[key];
          if (assigned == null || !aliasKeys.contains(key)) continue;
          if (!seen.add((assigned.id, ex.rawName))) continue;
          out.add((exerciseId: assigned.id, alias: ex.rawName));
        }
      }
    }
    return out;
  }

  /// PDF: el alumno para el que se importó. La vista previa mobile vive en
  /// una ruta por alumno y sólo muestra (y asigna) el borrador de ESE
  /// alumno: un borrador de A abierto en la ruta de B no es de B. `null` en
  /// el Excel del Coach Hub, que elige los alumnos al asignar.
  final String? athleteId;

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
  ///
  /// La alternativa NO se descarta: con «Confirmar las N sugerencias» el PF
  /// confirma en bloque y después revisa, y la alternativa es justo lo que
  /// necesita para corregir una sugerencia equivocada sin buscar en la
  /// biblioteca. La vista previa la oculta cuando ya es la asignada.
  ///
  /// Con [learn] la clave entra en [aliasKeys] (el PF eligió sobre el
  /// catálogo); sin él sale, así una fila reemplazada por un propio deja de
  /// enseñar el alias de antes.
  PeriodizedImportDraft resolve(
    ExerciseKey key,
    MatcherExercise exercise, {
    bool learn = false,
  }) {
    return PeriodizedImportDraft(
      plan: plan,
      warnings: warnings,
      name: name,
      assignments: {...assignments, key: exercise},
      suggestions: {...suggestions}..remove(key),
      alternatives: alternatives,
      aliasKeys: learn ? {...aliasKeys, key} : ({...aliasKeys}..remove(key)),
      athleteId: athleteId,
    );
  }

  /// Como [resolve], pero además asigna [exercise] a los OTROS componentes
  /// todavía sin candidato (ni asignación ni sugerencia) cuyo nombre
  /// normalizado es idéntico al de [key]. Es lo que corresponde al crear un
  /// ejercicio propio: «Press X» repetido en tres días es UN ejercicio.
  /// Nunca toca componentes con otro nombre, aunque se parezcan. Un propio
  /// no enseña alias: [key] sale de [aliasKeys].
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
      aliasKeys: {...aliasKeys}..remove(key),
      athleteId: athleteId,
    );
  }

  PeriodizedImportDraft withName(String value) => PeriodizedImportDraft(
        plan: plan,
        warnings: warnings,
        name: value,
        assignments: assignments,
        suggestions: suggestions,
        alternatives: alternatives,
        aliasKeys: aliasKeys,
        athleteId: athleteId,
      );

  /// El mismo borrador, atado a [id].
  PeriodizedImportDraft forAthlete(String id) => PeriodizedImportDraft(
        plan: plan,
        warnings: warnings,
        name: name,
        assignments: assignments,
        suggestions: suggestions,
        alternatives: alternatives,
        aliasKeys: aliasKeys,
        athleteId: id,
      );
}
