import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/routine.dart';
import '../domain/routine_visibility.dart';
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

/// Public subset of [userCreatedRoutinesProvider] — filters the same stream
/// down to routines the user explicitly marked `visibility: public`. Powers
/// the "RUTINAS PÚBLICAS" tab of another user's public profile screen.
///
/// Client-side filter (no extra Firestore listener) because the volume is
/// naturally bounded — a single user's routines rarely exceed a handful, and
/// the parent query already restricts by `createdBy == uid`. Adding a fourth
/// `where('visibility')` would require a new composite index just to save
/// filtering ~5 items in memory.
///
/// Returns an empty list when the source stream is loading or errored so
/// consumers never render stale content.
final publicRoutinesByUserProvider =
    Provider.autoDispose.family<List<Routine>, String>(
  (ref, uid) {
    return ref.watch(userCreatedRoutinesProvider(uid)).maybeWhen(
          data: (all) => all
              .where((r) => r.visibility == RoutineVisibility.public)
              .toList(growable: false),
          orElse: () => const [],
        );
  },
);
