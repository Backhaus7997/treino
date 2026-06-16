// Regression test: a failed repo.finish() write must NOT permanently finalize
// the notifier. Before the fix, finishSession/abandonSession called _finalize()
// (cancelling the timer + setting _finalized=true) BEFORE awaiting repo.finish.
// A throwing write then left the session active in Firestore while the local
// notifier was dead and frozen — no retry possible. The fix awaits the write
// first and resets _finalized on failure so the user can retry.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/features/workout/application/session_init.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';

import '../../../helpers/fake_analytics_service.dart';
import 'stub_factories.dart';

class MockSessionRepository extends Mock implements SessionRepository {}

ProviderContainer _makeContainer({
  required MockSessionRepository repo,
  required String uid,
  required Routine routine,
}) {
  return ProviderContainer(
    overrides: [
      sessionRepositoryProvider.overrideWithValue(repo),
      currentUidProvider.overrideWithValue(uid),
      analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
      routineByIdProvider(routine.id).overrideWith((ref) async => routine),
    ],
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(makeSession());
    registerFallbackValue(makeSetLog());
  });

  group('SessionNotifier finish/abandon write failure keeps notifier usable',
      () {
    test(
        'abandonSession: failed repo.finish rethrows and a retry succeeds '
        '(not permanently finalized)', () async {
      final repo = MockSessionRepository();
      final routine = makeRoutine();

      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
            weekNumber: any(named: 'weekNumber'),
          )).thenAnswer((_) async => makeSession());

      // First finish throws (offline / Firestore error), second succeeds.
      var calls = 0;
      when(() => repo.finish(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            finishedAt: any(named: 'finishedAt'),
            totalVolumeKg: any(named: 'totalVolumeKg'),
            durationMin: any(named: 'durationMin'),
            wasFullyCompleted: any(named: 'wasFullyCompleted'),
          )).thenAnswer((_) async {
        calls++;
        if (calls == 1) throw Exception('firestore write failed');
      });

      final container = _makeContainer(repo: repo, uid: 'u1', routine: routine);
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      await container.read(sessionNotifierProvider(init).future);
      final notifier = container.read(sessionNotifierProvider(init).notifier);

      // First attempt: the write fails and the error must propagate so the UI
      // does NOT navigate away.
      await expectLater(notifier.abandonSession(), throwsA(isA<Exception>()));

      // Retry: because the notifier was not permanently finalized, this call
      // must re-invoke repo.finish and complete successfully.
      await notifier.abandonSession();

      verify(() => repo.finish(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            finishedAt: any(named: 'finishedAt'),
            totalVolumeKg: any(named: 'totalVolumeKg'),
            durationMin: any(named: 'durationMin'),
            wasFullyCompleted: any(named: 'wasFullyCompleted'),
          )).called(2);
    });

    test(
        'finishSession: failed repo.finish rethrows and a retry succeeds '
        '(not permanently finalized)', () async {
      final repo = MockSessionRepository();
      // Single 1-set exercise so the session can become isFullyCompleted.
      final routine = makeRoutine(
        days: [
          makeDay(slots: [makeSlot(exerciseId: 'e1', targetSets: 1)])
        ],
      );

      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
            weekNumber: any(named: 'weekNumber'),
          )).thenAnswer((_) async => makeSession());
      when(() => repo.addSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).thenAnswer((_) async => makeSetLog());

      var calls = 0;
      when(() => repo.finish(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            finishedAt: any(named: 'finishedAt'),
            totalVolumeKg: any(named: 'totalVolumeKg'),
            durationMin: any(named: 'durationMin'),
            wasFullyCompleted: any(named: 'wasFullyCompleted'),
          )).thenAnswer((_) async {
        calls++;
        if (calls == 1) throw Exception('firestore write failed');
      });

      final container = _makeContainer(repo: repo, uid: 'u1', routine: routine);
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      await container.read(sessionNotifierProvider(init).future);
      final notifier = container.read(sessionNotifierProvider(init).notifier);

      // Complete the session so finishSession is allowed.
      await notifier.logSet(makeSetLog(exerciseId: 'e1', setNumber: 1));

      // First attempt fails → error propagates.
      await expectLater(notifier.finishSession(), throwsA(isA<Exception>()));

      // Retry succeeds because the notifier stayed usable.
      await notifier.finishSession();

      verify(() => repo.finish(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            finishedAt: any(named: 'finishedAt'),
            totalVolumeKg: any(named: 'totalVolumeKg'),
            durationMin: any(named: 'durationMin'),
            wasFullyCompleted: any(named: 'wasFullyCompleted'),
          )).called(2);
    });
  });
}
