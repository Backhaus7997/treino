import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workout/application/exercise_providers.dart';
import '../data/plan_import_repository.dart';
import '../data/periodized_import_draft.dart';

final planImportRepositoryProvider = Provider<PlanImportRepository>((ref) {
  return PlanImportRepository(
    exerciseRepository: ref.watch(exerciseRepositoryProvider),
  );
});

/// Estado del import en memoria — la vista previa lo consume después de que
/// la pantalla de subir empuje el resultado acá.
final periodizedImportProvider =
    StateProvider<PeriodizedImportDraft?>((ref) => null);
