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
