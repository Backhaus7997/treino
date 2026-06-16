import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/check_in/data/check_in_repository.dart';
import 'package:treino/features/check_in/domain/check_in.dart';

/// Regression: createTodayCheckIn must not clobber an existing same-day record.
/// The existence-check + write run inside a transaction (transactional
/// check-and-set), so a second create for the same day returns the original
/// record unchanged instead of overwriting checkedInAt / gym fields.
///
/// NOTE: fake_cloud_firestore's runTransaction is a no-op wrapper that does not
/// simulate real concurrency/serialization, so a true two-writers race cannot
/// be asserted here. We assert the production-meaningful invariant the fake CAN
/// verify: sequential idempotency — exactly one doc, second call returns the
/// first record without overwriting it. Real transactional isolation is
/// exercised against the emulator/production Firestore.
void main() {
  late FakeFirebaseFirestore firestore;
  late CheckInRepository repo;

  const uid = 'user-concurrent-001';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = CheckInRepository(firestore: firestore);
  });

  test(
      'createTodayCheckIn is idempotent: a second same-day call returns the '
      'existing record without overwriting it', () async {
    // First check-in (in a gym).
    final first = await repo.createTodayCheckIn(
      uid,
      inGym: true,
      gymId: 'gym1',
      gymName: 'Smart Fit',
    );

    // Second call the same day with different params must NOT win.
    final second = await repo.createTodayCheckIn(
      uid,
      inGym: false,
    );

    // Exactly one doc must exist for today.
    final today = CheckIn.dateKey(DateTime.now().toLocal());
    final col = await firestore
        .collection('users')
        .doc(uid)
        .collection('checkIns')
        .get();
    expect(col.docs.where((d) => d.id == today).length, equals(1));

    // The second call returns the original record unchanged (the transactional
    // check-and-set returns the existing doc rather than overwriting it).
    expect(second!.gymId, equals('gym1'));
    expect(second.gymName, equals('Smart Fit'));
    expect(second.checkedInAt, equals(first!.checkedInAt));

    final stored = await repo.getTodayForUser(uid);
    expect(stored, isNotNull);
    expect(stored!.gymId, equals('gym1'));
    expect(stored.checkedInAt, equals(first.checkedInAt));
  });
}
