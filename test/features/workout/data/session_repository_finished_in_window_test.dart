import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/data/session_repository.dart';

/// Focused coverage for SessionRepository.listFinishedInWindow — bounded
/// server-side query that powers the inactivos provider.
void main() {
  late FakeFirebaseFirestore firestore;
  late SessionRepository repo;

  const uid = 'athlete-fw-001';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = SessionRepository(firestore: firestore);
  });

  // Stable "now" = 2026-06-16 12:00 UTC
  final now = DateTime.utc(2026, 6, 16, 12, 0, 0);
  // 14-day window: from=2026-06-02 00:00 UTC, to=2026-06-17 00:00 UTC
  final todayStart = DateTime.utc(now.year, now.month, now.day);
  final from = todayStart.subtract(const Duration(days: 14));
  final to = todayStart.add(const Duration(days: 1));

  Future<void> seedSession({
    required String id,
    required String status,
    DateTime? finishedAt,
  }) async {
    await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(id)
        .set({
      'id': id,
      'uid': uid,
      'routineId': 'r1',
      'routineName': 'Routine',
      'startedAt': Timestamp.fromDate(
        (finishedAt ?? now).subtract(const Duration(hours: 1)),
      ),
      'finishedAt':
          finishedAt == null ? null : Timestamp.fromDate(finishedAt),
      'totalVolumeKg': 0.0,
      'durationMin': 0,
      'status': status,
      'dayNumber': 1,
      'weekNumber': 0,
    });
  }

  test('returns sessions finished within the window, excluding boundaries',
      () async {
    // Inside window — should be included.
    await seedSession(
      id: 'in-window',
      status: 'finished',
      finishedAt: DateTime.utc(2026, 6, 10, 12, 0, 0),
    );
    // On lower boundary (from) — should be included (isGreaterThanOrEqualTo).
    await seedSession(
      id: 'on-from',
      status: 'finished',
      finishedAt: from,
    );
    // Before window — should be excluded.
    await seedSession(
      id: 'before-window',
      status: 'finished',
      finishedAt: DateTime.utc(2026, 6, 1, 23, 59, 0),
    );
    // On upper boundary (to) — excluded in Dart filter (finishedAt < to).
    await seedSession(
      id: 'on-to',
      status: 'finished',
      finishedAt: to,
    );
    // After window — should be excluded.
    await seedSession(
      id: 'after-window',
      status: 'finished',
      finishedAt: DateTime.utc(2026, 6, 18, 0, 0, 0),
    );
    // Active session in window — wrong status, must be excluded.
    await seedSession(
      id: 'active-in-window',
      status: 'active',
      finishedAt: null,
    );

    final results =
        await repo.listFinishedInWindow(uid, from: from, to: to);

    final ids = results.map((s) => s.id).toSet();
    expect(ids, containsAll(['in-window', 'on-from']));
    expect(ids, isNot(contains('before-window')));
    expect(ids, isNot(contains('on-to')));
    expect(ids, isNot(contains('after-window')));
    expect(ids, isNot(contains('active-in-window')));
  });

  test('returns empty list when no sessions finished in window', () async {
    await seedSession(
      id: 'old',
      status: 'finished',
      finishedAt: DateTime.utc(2026, 5, 1, 10, 0, 0),
    );

    final results =
        await repo.listFinishedInWindow(uid, from: from, to: to);

    expect(results, isEmpty);
  });

  test('returns empty list for empty uid', () async {
    final results =
        await repo.listFinishedInWindow('', from: from, to: to);
    expect(results, isEmpty);
  });
}
