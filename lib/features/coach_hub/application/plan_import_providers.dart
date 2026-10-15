import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../workout/application/custom_exercise_providers.dart';
import '../../workout/application/exercise_providers.dart';
import '../data/plan_import_repository.dart';
import '../data/periodized_import_draft.dart';

final planImportRepositoryProvider = Provider<PlanImportRepository>((ref) {
  return PlanImportRepository(
    exerciseRepository: ref.watch(exerciseRepositoryProvider),
    customExercises: () async {
      final uid = ref.read(currentUidProvider);
      if (uid == null || uid.isEmpty) return const [];
      // Si el stream tarda, no se frena el import: se sigue sin propios.
      return ref
          .read(customExercisesForTrainerStreamProvider(uid).future)
          .timeout(const Duration(seconds: 5));
    },
  );
});

/// Estado del import en memoria — la vista previa lo consume después de que
/// la pantalla de subir empuje el resultado acá.
final periodizedImportProvider =
    StateProvider<PeriodizedImportDraft?>((ref) => null);
