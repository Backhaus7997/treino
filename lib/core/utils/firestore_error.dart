import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;

/// Whether [error] is a Firestore `permission-denied` failure.
///
/// Lets an EXPECTED access denial be told apart from a real backend failure.
/// A trainer reading an athlete's sessions is denied (`permission-denied`) when
/// that athlete has not opted into `session_shares` — an expected, per-athlete
/// condition, so the athlete is skipped silently. Any OTHER Firestore error
/// (missing composite index → `failed-precondition`, backend `unavailable`, …)
/// is a genuine failure that must surface, so an empty result is never mistaken
/// for a legitimate "nothing here".
///
/// Mirrors the `permission-denied` vs "every other code" split already used by
/// [RoutineRepository.getByIdIfVisible].
bool isPermissionDenied(Object? error) =>
    error is FirebaseException && error.code == 'permission-denied';
