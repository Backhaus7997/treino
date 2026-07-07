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
      'finishedAt': finishedAt == null ? null : Timestamp.fromDate(finishedAt),
      'totalVolumeKg': 0.0,
      'durationMin': 0,
      'status': status,
      'dayNumber': 1,
      'weekNumber': 0,
    });
  }

  test('listFinishedToday buckets by the ART calendar day, newest-first',
      () async {
    // now = 2026-06-16 12:00 UTC = 09:00 ART → ART "today" is 2026-06-16,
    // i.e. the UTC window [Jun 16 03:00, Jun 17 03:00).
    await seedSession(
      id: 'today-early',
      status: 'finished',
      finishedAt: DateTime.utc(2026, 6, 16, 8, 0, 0), // 05:00 ART — today
    );
    await seedSession(
      id: 'today-late',
      status: 'finished',
      finishedAt: DateTime.utc(2026, 6, 16, 20, 30, 0), // 17:30 ART — today
    );
    // 01:00 UTC Jun 17 == 22:00 ART Jun 16 → still TODAY in ART. This is the
    // case the old UTC-day math dropped (it read it as tomorrow).
    await seedSession(
      id: 'art-today-evening',
      status: 'finished',
      finishedAt: DateTime.utc(2026, 6, 17, 1, 0, 0),
    );
    // 02:00 UTC Jun 16 == 23:00 ART Jun 15 → yesterday ART, excluded.
    await seedSession(
      id: 'art-yesterday',
      status: 'finished',
      finishedAt: DateTime.utc(2026, 6, 16, 2, 0, 0),
    );
    // 04:00 UTC Jun 17 == 01:00 ART Jun 17 → tomorrow ART, excluded.
    await seedSession(
      id: 'art-tomorrow',
      status: 'finished',
      finishedAt: DateTime.utc(2026, 6, 17, 4, 0, 0),
    );
    // Active session — excluded (wrong status).
    await seedSession(id: 'active', status: 'active');

    final results = await repo.listFinishedToday(uid, now: now);

    expect(results.map((s) => s.id),
        ['art-today-evening', 'today-late', 'today-early']);
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
