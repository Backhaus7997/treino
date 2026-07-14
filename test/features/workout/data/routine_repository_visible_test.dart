import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';

/// [RoutineRepository.getByIdIfVisible] — the ONE place that decides which
/// Firestore failures mean "you cannot have this routine" (→ null) and which are
/// real failures that must keep propagating (→ rethrow).
///
/// `fake_cloud_firestore` cannot produce these on its own: it does not evaluate
/// security rules, so it can never return `permission-denied`. Rather than mock
/// the sealed `CollectionReference`/`DocumentReference` types, this drives the
/// error path through the one seam that matters — `getById`, which
/// `getByIdIfVisible` delegates to.
class _FailingRepo extends RoutineRepository {
  _FailingRepo(this.error) : super(firestore: FakeFirebaseFirestore());

  final Object error;

  @override
  Future<Routine?> getById(String id) async => throw error;
}

FirebaseException _firestoreError(String code) =>
    FirebaseException(plugin: 'cloud_firestore', code: code);

void main() {
  group('getByIdIfVisible — absorbs "you cannot have this routine"', () {
    test('permission-denied → null (does NOT throw)', () async {
      // The real case this exists for: a `trainer-template` an athlete trained
      // from while the trainer had `sharedTemplatesWithAthletes` on, after the
      // trainer flipped it off. Old sessions reference that routineId forever.
      // Covered end-to-end by SCENARIO-611 in scripts/rules_test/rules.test.js.
      final repo = _FailingRepo(_firestoreError('permission-denied'));

      await expectLater(repo.getByIdIfVisible('r1'), completion(isNull));
    });

    test('not-found → null (does NOT throw)', () async {
      final repo = _FailingRepo(_firestoreError('not-found'));

      await expectLater(repo.getByIdIfVisible('r1'), completion(isNull));
    });
  });

  group('getByIdIfVisible — RETHROWS everything else', () {
    // This is the half the first implementation got wrong. A blanket
    // `.onError<Object>((_, __) => null)` swallowed these too, which does NOT
    // degrade gracefully — it silently produces a WRONG chart: the radar axes
    // lose that routine's custom-exercise sets while the header total still
    // counts them. Same user, same data, different chart depending on network
    // luck, with no error shown. A transient failure must stay retryable.
    test('unavailable (network blip) → rethrows', () async {
      final repo = _FailingRepo(_firestoreError('unavailable'));

      await expectLater(
        repo.getByIdIfVisible('r1'),
        throwsA(isA<FirebaseException>()
            .having((e) => e.code, 'code', 'unavailable')),
      );
    });

    test('deadline-exceeded → rethrows', () async {
      final repo = _FailingRepo(_firestoreError('deadline-exceeded'));

      await expectLater(
        repo.getByIdIfVisible('r1'),
        throwsA(isA<FirebaseException>()),
      );
    });

    test('a non-Firebase error (e.g. malformed doc) → rethrows', () async {
      // `onError<Object>` also swallowed genuine bugs — a TypeError out of
      // Routine.fromJson, a StateError — making them permanently invisible.
      final repo = _FailingRepo(StateError('malformed routine doc'));

      await expectLater(
        repo.getByIdIfVisible('r1'),
        throwsA(isA<StateError>()),
      );
    });
  });

  test('a routine that simply does not exist resolves to null', () async {
    // The happy path after the firestore.rules existence guard: the read now
    // SUCCEEDS with an empty snapshot instead of coming back permission-denied,
    // so `_fromDoc`'s `!snap.exists` guard finally runs. Uses the real (fake)
    // Firestore, not the failing double.
    final repo = RoutineRepository(firestore: FakeFirebaseFirestore());

    await expectLater(repo.getByIdIfVisible('nope'), completion(isNull));
    await expectLater(repo.getById('nope'), completion(isNull));
  });
}
