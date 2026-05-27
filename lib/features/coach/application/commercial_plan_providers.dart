import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/commercial_plan_repository.dart';
import '../domain/commercial_plan.dart';

/// Singleton repository.
final commercialPlanRepositoryProvider = Provider<CommercialPlanRepository>(
  (ref) => CommercialPlanRepository(
    firestore: ref.watch(firestoreProvider),
  ),
);

/// Real-time stream of plans for a given trainer, ordered by createdAt desc.
///
/// Returns ALL statuses (active + archived). UI filters as needed.
final commercialPlansForTrainerStreamProvider = StreamProvider.autoDispose
    .family<List<CommercialPlan>, String>((ref, trainerId) {
  return ref.read(commercialPlanRepositoryProvider).watchForTrainer(trainerId);
});
