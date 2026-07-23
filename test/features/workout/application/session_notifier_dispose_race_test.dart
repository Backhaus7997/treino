// TRIPWIRES for the #497 dispose-race finding (P1, confidence: medium) —
// AUDITED AND NOT REPRODUCIBLE on riverpod 2.6.1. These tests pin the behavior
// the current code silently depends on, so a riverpod upgrade that tightens it
// fails HERE instead of silently losing an athlete's finished workout.
//
// The finding: the session player guards its route with
// `PopScope(canPop: _isFinalizing)`, and `_isFinalizing` flips to true the
// moment TERMINAR is tapped — so a pop IS allowed while `repo.finish` is still
// in flight. The route leaves, the last listener on this
// `AutoDisposeFamilyAsyncNotifier` goes away, and the notifier IS torn down
// mid-await (SCENARIO-497-020 proves the teardown really happens: the
// continuation resumes on a disposed element). The predicted symptom was that
// `ref.invalidate(sessionsByUidProvider)` + analytics + `state =` would then
// throw or no-op, persisting the finish while historial stayed stale.
//
// It does not happen on 2.6.1: `Ref.invalidate` and `Ref.read` delegate
// straight to the container, which is still alive, and assigning `state` on a
// disposed element is a tolerated no-op. The invalidate lands, the analytics
// event lands, nothing throws. Riverpod 3.x makes `ref` use-after-dispose an
// error — when this repo migrates, these tests go red and the fix
// (`ref.keepAlive()` across the write + a `_disposed` guard) becomes required.

import 'dart:async';

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

/// Counts how many times the session cache was (re)fetched, so a test can prove
/// the post-write `ref.invalidate(sessionsByUidProvider(uid))` actually landed.
class _SessionCacheProbe {
  int fetches = 0;
}

ProviderContainer _makeContainer({
  required MockSessionRepository repo,
  required FakeAnalyticsService analytics,
  required Routine routine,
  required _SessionCacheProbe probe,
}) {
  return ProviderContainer(
    overrides: [
      sessionRepositoryProvider.overrideWithValue(repo),
      currentUidProvider.overrideWithValue('u1'),
      analyticsServiceProvider.overrideWithValue(analytics),
      routineByIdProvider(routine.id).overrideWith((ref) async => routine),
      sessionsByUidProvider('u1').overrideWith((ref) async {
        probe.fetches++;
        return const [];
      }),
    ],
  );
}

/// A single 1-set exercise so the session can reach `isFullyCompleted`.
Routine _oneSetRoutine() => makeRoutine(
      days: [
        makeDay(slots: [makeSlot(exerciseId: 'e1', targetSets: 1)])
      ],
    );

void _stubCreateAndLog(MockSessionRepository repo) {
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
}

/// Makes `repo.finish` hang until the returned completer is completed, so the
/// test can tear the notifier down while the write is mid-flight.
Completer<void> _gateFinish(MockSessionRepository repo) {
  final gate = Completer<void>();
  when(() => repo.finish(
        uid: any(named: 'uid'),
        sessionId: any(named: 'sessionId'),
        finishedAt: any(named: 'finishedAt'),
        totalVolumeKg: any(named: 'totalVolumeKg'),
        durationMin: any(named: 'durationMin'),
        wasFullyCompleted: any(named: 'wasFullyCompleted'),
      )).thenAnswer((_) => gate.future);
  return gate;
}

void main() {
  setUpAll(() {
    registerFallbackValue(makeSession());
    registerFallbackValue(makeSetLog());
  });

  group('SessionNotifier post-write side effects survive a mid-write dispose',
      () {
    test(
        'SCENARIO-497-020: finishSession — the route pops mid-write, the '
        'notifier IS torn down, and the cache refresh + analytics still land',
        () async {
      final repo = MockSessionRepository();
      final analytics = FakeAnalyticsService();
      final probe = _SessionCacheProbe();
      final routine = _oneSetRoutine();
      _stubCreateAndLog(repo);

      final container = _makeContainer(
        repo: repo,
        analytics: analytics,
        routine: routine,
        probe: probe,
      );
      addTearDown(container.dispose);

      // The shell screens above the player keep watching the session cache the
      // whole workout — that is why the finish must invalidate it explicitly.
      final shellSub = container.listen(
        sessionsByUidProvider('u1'),
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(shellSub.close);
      await container.read(sessionsByUidProvider('u1').future);
      expect(probe.fetches, 1);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      // The player screen's own subscription — closing it is the swipe-back.
      final playerSub = container.listen(
        sessionNotifierProvider(init),
        (_, __) {},
        fireImmediately: true,
      );
      await container.read(sessionNotifierProvider(init).future);
      final notifier = container.read(sessionNotifierProvider(init).notifier);
      await notifier.logSet(makeSetLog(exerciseId: 'e1', setNumber: 1));

      final gate = _gateFinish(repo);
      final pending = notifier.finishSession();

      // User swipes back while the Firestore write is still in flight.
      playerSub.close();
      await container.pump();

      // The teardown is real: the provider now hands out a NEW notifier, so the
      // in-flight `finishSession` really is resuming on a disposed element.
      expect(
        identical(
            container.read(sessionNotifierProvider(init).notifier), notifier),
        isFalse,
        reason: 'the mid-write dispose must actually happen for this to test '
            'anything',
      );

      gate.complete();
      await expectLater(pending, completes);
      await container.pump();

      expect(
        probe.fetches,
        2,
        reason: 'the historial refresh must land even though the player left',
      );
      expect(
        analytics.events,
        contains('routine_finished'),
        reason: 'the analytics event must not be lost to the pop',
      );
    });

    test(
        'SCENARIO-497-021: abandonSession — same teardown, cache refresh still '
        'lands', () async {
      final repo = MockSessionRepository();
      final analytics = FakeAnalyticsService();
      final probe = _SessionCacheProbe();
      final routine = makeRoutine();
      _stubCreateAndLog(repo);

      final container = _makeContainer(
        repo: repo,
        analytics: analytics,
        routine: routine,
        probe: probe,
      );
      addTearDown(container.dispose);

      final shellSub = container.listen(
        sessionsByUidProvider('u1'),
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(shellSub.close);
      await container.read(sessionsByUidProvider('u1').future);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      final playerSub = container.listen(
        sessionNotifierProvider(init),
        (_, __) {},
        fireImmediately: true,
      );
      await container.read(sessionNotifierProvider(init).future);
      final notifier = container.read(sessionNotifierProvider(init).notifier);

      final gate = _gateFinish(repo);
      final pending = notifier.abandonSession();

      playerSub.close();
      await container.pump();

      gate.complete();
      await expectLater(pending, completes);
      await container.pump();

      expect(probe.fetches, 2);
      // Abandons are deliberately NOT a `routine_finished` event.
      expect(analytics.events, isEmpty);
    });

    test(
        'SCENARIO-497-022: an EXPLICIT teardown mid-write is survived too '
        '(logout, or a forced rebuild — `keepAlive` could not block these)',
        () async {
      final repo = MockSessionRepository();
      final analytics = FakeAnalyticsService();
      final probe = _SessionCacheProbe();
      final routine = makeRoutine();
      _stubCreateAndLog(repo);

      final container = _makeContainer(
        repo: repo,
        analytics: analytics,
        routine: routine,
        probe: probe,
      );
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      await container.read(sessionNotifierProvider(init).future);
      final notifier = container.read(sessionNotifierProvider(init).notifier);

      final gate = _gateFinish(repo);
      final pending = notifier.abandonSession();

      container.invalidate(sessionNotifierProvider(init));
      await container.pump();

      gate.complete();
      await expectLater(pending, completes);
    });
  });
}
