// Regression test for the updateSet pre-await snapshot race.
//
// Bug: updateSet captured `current = state.value` BEFORE the Firestore await,
// then rebuilt setLogs from that stale `current` after the await. A logSet
// that completed during the updateSet await was silently dropped from state,
// because updateSet overwrote state with the older snapshot.
//
// Fix: updateSet re-reads `state.value` after the await (mirroring logSet),
// so a concurrent logSet's persisted entry survives.
//
// This file is intentionally separate from session_notifier_test.dart to avoid
// collisions with other agents editing the shared suite in parallel.

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

  test(
      'updateSet preserves a logSet that completes during its await '
      '(no stale-snapshot overwrite)', () async {
    final repo = MockSessionRepository();
    final session = makeSession();
    final routine = makeRoutine(
      days: [
        makeDay(slots: [
          makeSlot(exerciseId: 'e1', targetSets: 3),
        ])
      ],
    );

    when(() => repo.create(
          uid: any(named: 'uid'),
          routineId: any(named: 'routineId'),
          routineName: any(named: 'routineName'),
          startedAt: any(named: 'startedAt'),
          dayNumber: any(named: 'dayNumber'),
          weekNumber: any(named: 'weekNumber'),
        )).thenAnswer((_) async => session);

    // logSet echoes back the persisted SetLog so it lands in state with its id.
    when(() => repo.addSetLog(
          uid: any(named: 'uid'),
          sessionId: any(named: 'sessionId'),
          setLog: any(named: 'setLog'),
        )).thenAnswer(
      (inv) async => inv.namedArguments[const Symbol('setLog')] as dynamic,
    );

    // Gate updateSetLog so we can deterministically interleave a logSet
    // while updateSet is still awaiting the write.
    final updateGate = Completer<void>();
    when(() => repo.updateSetLog(
          uid: any(named: 'uid'),
          sessionId: any(named: 'sessionId'),
          setLog: any(named: 'setLog'),
        )).thenAnswer((_) => updateGate.future);

    final container = _makeContainer(repo: repo, uid: 'u1', routine: routine);
    addTearDown(container.dispose);

    final init = FreshSession(routineId: routine.id, dayNumber: 1);
    await container.read(sessionNotifierProvider(init).future);
    final notifier = container.read(sessionNotifierProvider(init).notifier);

    // Seed an existing set (id 'l1') that we will edit via updateSet.
    await notifier.logSet(
      makeSetLog(exerciseId: 'e1', setNumber: 1, id: 'l1', reps: 8),
    );
    expect(
      container.read(sessionNotifierProvider(init)).value!.setLogs,
      hasLength(1),
    );

    // Start updateSet on the existing set — it awaits the gated updateSetLog
    // and snapshots state.value (1 log) BEFORE the await resolves.
    final updateFuture = notifier.updateSet(
      makeSetLog(exerciseId: 'e1', setNumber: 1, id: 'l1', reps: 12),
    );

    // While updateSet is in flight, a new set (id 'l2') is logged and lands
    // in state. logSet has no gate, so this completes first.
    await notifier.logSet(
      makeSetLog(exerciseId: 'e1', setNumber: 2, id: 'l2', reps: 10),
    );
    expect(
      container.read(sessionNotifierProvider(init)).value!.setLogs,
      hasLength(2),
      reason: 'logSet must have appended l2 before updateSet resolves',
    );

    // Now let updateSet finish.
    updateGate.complete();
    await updateFuture;

    final logs = container.read(sessionNotifierProvider(init)).value!.setLogs;

    // Both the edit AND the concurrent log must survive.
    expect(logs, hasLength(2),
        reason: 'updateSet must not drop the concurrently logged l2');
    final ids = logs.map((l) => l.id).toSet();
    expect(ids, containsAll(<String>{'l1', 'l2'}));
    final edited = logs.firstWhere((l) => l.id == 'l1');
    expect(edited.reps, equals(12), reason: 'the edit must be applied');
  });
}
