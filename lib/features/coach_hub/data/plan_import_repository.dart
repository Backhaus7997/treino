import 'dart:typed_data';

import '../../workout/data/exercise_repository.dart';
import '../../workout/domain/custom_exercise.dart';
import 'periodized_import_draft.dart';
import '../domain/periodized_plan.dart';
import 'periodized_excel_parser.dart';
import 'plan_draft_matcher.dart';

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

/// Coordina el flujo de import client-side del Excel:
/// 1. Parsea el .xlsx en memoria con `parsePeriodizedExcel`
/// 2. Si no hay errores, delega en [PlanDraftMatcher]: lee el catálogo,
///    pasa CADA componente por el matcher (#1455) y arma el borrador
///
/// La seguridad real está en Firestore rules — este repo solo hace UX.
class PlanImportRepository {
  PlanImportRepository({
    required ExerciseRepository exerciseRepository,
    Future<List<CustomExercise>> Function()? customExercises,
  }) : _matcher = PlanDraftMatcher(
          exerciseRepository: exerciseRepository,
          customExercises: customExercises,
        );

  final PlanDraftMatcher _matcher;

  /// [defaultName] es el nombre inicial de la rutina (el del archivo).
  Future<PlanImportOutcome> parseAndMatch({
    required Uint8List bytes,
    String defaultName = 'Plan importado',
  }) async {
    final parsed = parsePeriodizedExcel(bytes);
    if (!parsed.canImport) {
      return PlanImportOutcome(diagnostics: parsed.diagnostics);
    }

    return PlanImportOutcome(
      diagnostics: parsed.diagnostics,
      draft: await _matcher.matchDraft(
        plan: parsed.plan!,
        warnings: parsed.warnings,
        name: defaultName,
      ),
    );
  }
}
