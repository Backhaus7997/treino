import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/routine.dart';
import 'routine_providers.dart' show routineRepositoryProvider;

/// Returns a live stream of the athlete's own active routines, ordered
/// newest first.
///
/// Returns an empty stream immediately when [uid] is empty — avoids a
/// Firestore round-trip for unauthenticated or unresolved uid states.
///
/// `autoDispose` ensures the provider is cleaned up when no widget is
/// listening. `family` lets each uid maintain its own cached stream.
///
/// Powered by [RoutineRepository.listUserCreated] which applies the
/// composite index on `(createdBy, source, status, createdAt)` declared in
/// `firestore.indexes.json` (REQ-USR-017).
///
/// REQ-USR-002, REQ-USR-007, ADR design §application layer.
final userCreatedRoutinesProvider =
    StreamProvider.autoDispose.family<List<Routine>, String>(
  (ref, uid) {
    if (uid.isEmpty) return Stream.value(const []);
    return ref.watch(routineRepositoryProvider).listUserCreated(uid);
  },
);
