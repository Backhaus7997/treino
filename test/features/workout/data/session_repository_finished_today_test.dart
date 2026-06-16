import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/data/session_repository.dart';

/// Focused coverage for SessionRepository.listFinishedToday — the bounded
/// server-side query that replaced the per-athlete full-history read in
/// trainedTodayProvider (N+1 / over-fetch fix).
void main() {
  late FakeFirebaseFirestore firestore;
  late SessionRepository repo;

  const uid = 'athlete-tt-001';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = SessionRepository(firestore: firestore);
  });

  // Fixed "now" so the day window is deterministic.
  final now = DateTime.utc(2026, 6, 16, 12, 0, 0);

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

  test('listFinishedToday returns only today\'s finished sessions, newest-first',
      () async {
    // Two finished today (different hours).
    await seedSession(
      id: 'today-early',
      status: 'finished',
      finishedAt: DateTime.utc(2026, 6, 16, 8, 0, 0),
    );
    await seedSession(
      id: 'today-late',
      status: 'finished',
      finishedAt: DateTime.utc(2026, 6, 16, 20, 30, 0),
    );
    // Finished yesterday — must be excluded.
    await seedSession(
      id: 'yesterday',
      status: 'finished',
      finishedAt: DateTime.utc(2026, 6, 15, 23, 59, 0),
    );
    // Finished tomorrow (edge) — must be excluded.
    await seedSession(
      id: 'tomorrow',
      status: 'finished',
      finishedAt: DateTime.utc(2026, 6, 17, 0, 0, 0),
    );
    // Active session today — must be excluded (wrong status).
    await seedSession(id: 'active', status: 'active');

    final results = await repo.listFinishedToday(uid, now: now);

    expect(results.map((s) => s.id), ['today-late', 'today-early']);
  });

  test('listFinishedToday returns empty list when nothing finished today',
      () async {
    await seedSession(
      id: 'yesterday',
      status: 'finished',
      finishedAt: DateTime.utc(2026, 6, 15, 10, 0, 0),
    );
    await seedSession(id: 'active', status: 'active');

    final results = await repo.listFinishedToday(uid, now: now);

    expect(results, isEmpty);
  });
}
