import '../../workout/data/exercise_repository.dart';
import '../../workout/domain/custom_exercise.dart';
import '../domain/periodized_plan.dart';
import 'exercise_matcher.dart';
import 'periodized_import_draft.dart';
import 'periodized_routine_mapper.dart';

/// Matchea un [PeriodizedPlan] ya leído contra el catálogo y arma el borrador
/// de la vista previa. No sabe de dónde salió el plan (Excel o PDF): por eso
/// vive aparte de `PlanImportRepository` y no arrastra `package:excel`.
///
/// La seguridad real está en Firestore rules — esto solo hace UX.
class PlanDraftMatcher {
  PlanDraftMatcher({
    required ExerciseRepository exerciseRepository,
    Future<List<CustomExercise>> Function()? customExercises,
  })  : _exerciseRepository = exerciseRepository,
        _customExercises = customExercises;

  final ExerciseRepository _exerciseRepository;

  /// Ejercicios propios del PF. Entran al catálogo del matcher para que
  /// re-importar un plan con un ejercicio ya creado como propio se asigne
  /// solo (exacto → auto; aproximado → sugerencia) y no invite a duplicarlo
  /// (cada duplicado consume el tope del plan). Si falla, se importa sólo
  /// con la biblioteca: nunca bloquea el import.
  final Future<List<CustomExercise>> Function()? _customExercises;

  /// Biblioteca + propios del PF, en la forma que usa el matcher.
  Future<List<MatcherExercise>> loadCatalog() async {
    final catalog = (await _exerciseRepository.listAll())
        .map((e) => MatcherExercise(
              id: e.id,
              name: e.name,
              muscleGroup: e.muscleGroup,
              aliases: e.aliases,
            ))
        .toList();

    // Mismo id crudo que usa el picker web para un propio: el atleta lo
    // resuelve por el dueño de la rutina (`assignedBy`).
    List<CustomExercise> customs = const [];
    try {
      customs = await _customExercises?.call() ?? const [];
    } catch (_) {
      // Sin propios: sólo biblioteca.
    }
    catalog.addAll(customs.map((c) => MatcherExercise(
          id: c.id,
          name: c.name,
          muscleGroup: c.muscleGroup,
        )));
    return catalog;
  }

  /// Pasa CADA componente de cada renglón por el matcher (#1455) y devuelve
  /// el borrador. [warnings] son los avisos del origen (parser o validador),
  /// [name] el nombre inicial de la rutina.
  Future<PeriodizedImportDraft> matchDraft({
    required PeriodizedPlan plan,
    required List<ImportDiagnostic> warnings,
    required String name,
  }) async {
    final match = matchPeriodizedPlan(plan, await loadCatalog());
    return PeriodizedImportDraft.fromMatch(
      plan: plan,
      warnings: warnings,
      name: name,
      match: match,
    );
  }
}
