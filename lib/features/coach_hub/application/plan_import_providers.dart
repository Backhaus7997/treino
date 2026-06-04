import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workout/application/exercise_providers.dart';
import '../data/plan_import_repository.dart';
import '../domain/parsed_plan.dart';
import '../domain/periodized_preview.dart';

final planImportRepositoryProvider = Provider<PlanImportRepository>((ref) {
  return PlanImportRepository(
    exerciseRepository: ref.watch(exerciseRepositoryProvider),
  );
});

/// Estado del import en memoria — el preview screen lo consume después
/// de que el upload screen empuje el resultado acá.
final parsedPlanProvider = StateProvider<ParsedPlan?>((ref) => null);

/// Igual que [parsedPlanProvider] pero para el formato periodizado. El upload
/// empuja a uno u otro según el formato detectado; el otro queda en null.
final parsedPeriodizedPlanProvider =
    StateProvider<PeriodizedPreviewPlan?>((ref) => null);
