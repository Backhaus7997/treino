import 'dart:typed_data';

import '../../workout/data/exercise_repository.dart';
import '../../workout/domain/custom_exercise.dart';
import 'periodized_import_draft.dart';
import '../domain/periodized_plan.dart';
import 'exercise_matcher.dart';
import 'periodized_excel_parser.dart';
import 'periodized_routine_mapper.dart';

/// Resultado de procesar un archivo: todos los diagnósticos del parser y, si
/// no hubo errores, el borrador listo para la vista previa.
class PlanImportOutcome {
  const PlanImportOutcome({required this.diagnostics, this.draft});

  final List<ImportDiagnostic> diagnostics;

  /// Null cuando el parser encontró errores: no se avanza.
  final PeriodizedImportDraft? draft;

  List<ImportDiagnostic> get errors =>
      diagnostics.where((d) => d.isError).toList(growable: false);
}

/// Coordina el flujo de import client-side:
/// 1. Parsea el .xlsx en memoria con `parsePeriodizedExcel`
/// 2. Si no hay errores, lee el catálogo `exercises` desde Firestore
/// 3. Pasa CADA componente de cada renglón por el matcher (#1455)
/// 4. Devuelve un borrador listo para mostrar en la vista previa
///
/// La seguridad real está en Firestore rules — este repo solo hace UX.
class PlanImportRepository {
  PlanImportRepository({
    required ExerciseRepository exerciseRepository,
    Future<List<CustomExercise>> Function()? customExercises,
  })  : _exerciseRepository = exerciseRepository,
        _customExercises = customExercises;

  final ExerciseRepository _exerciseRepository;

  /// Ejercicios propios del PF. Entran al catálogo del matcher para que
  /// re-importar una hoja con un ejercicio ya creado como propio se asigne
  /// solo (exacto → auto; aproximado → sugerencia) y no invite a duplicarlo
  /// (cada duplicado consume el tope del plan). Si falla, se importa sólo
  /// con la biblioteca: nunca bloquea el import.
  final Future<List<CustomExercise>> Function()? _customExercises;

  /// [defaultName] es el nombre inicial de la rutina (el del archivo).
  Future<PlanImportOutcome> parseAndMatch({
    required Uint8List bytes,
    String defaultName = 'Plan importado',
  }) async {
    final parsed = parsePeriodizedExcel(bytes);
    if (!parsed.canImport) {
      return PlanImportOutcome(diagnostics: parsed.diagnostics);
    }

    final plan = parsed.plan!;
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

    final match = matchPeriodizedPlan(plan, catalog);
    return PlanImportOutcome(
      diagnostics: parsed.diagnostics,
      draft: PeriodizedImportDraft.fromMatch(
        plan: plan,
        warnings: parsed.warnings,
        name: defaultName,
        match: match,
      ),
    );
  }
}
