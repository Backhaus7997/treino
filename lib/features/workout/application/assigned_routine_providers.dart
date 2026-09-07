import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/routine.dart';
import 'routine_providers.dart' show routineRepositoryProvider;

/// Returns all plans assigned to the given athlete uid by a trainer,
/// ordered newest first.
///
/// Returns an empty list immediately when [athleteId] is empty — avoids a
/// Firestore round-trip for unauthenticated or unresolved uid states.
///
/// `autoDispose` ensures the provider is cleaned up when no widget is
/// listening. `family` lets each athleteId maintain its own cached future.
///
/// REQ-COACH-PLANS-003, REQ-COACH-PLANS-004, SCENARIO-436, SCENARIO-437.
final assignedRoutinesProvider =
    FutureProvider.autoDispose.family<List<Routine>, String>(
  (ref, athleteId) async {
    if (athleteId.isEmpty) return const [];
    return ref.watch(routineRepositoryProvider).listAssignedTo(athleteId);
  },
);

/// Returns the plans one trainer assigned to one athlete, newest first.
///
/// Trainer reads need both ids in the Firestore query so security rules can
/// prove `assignedBy == request.auth.uid`. The record gives `.family`
/// structural equality and keeps each trainer/athlete pair in its own cache.
final assignedRoutinesByTrainerProvider = FutureProvider.autoDispose.family<
    List<Routine>, ({String trainerId, String athleteId})>(
  (ref, key) async {
    if (key.trainerId.isEmpty || key.athleteId.isEmpty) return const [];
    return ref.watch(routineRepositoryProvider).listAssignedToByTrainer(
          trainerId: key.trainerId,
          athleteId: key.athleteId,
        );
  },
);
