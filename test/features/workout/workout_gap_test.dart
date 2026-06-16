// Gap tests for the `workout` module — generated to extend the existing suite
// under test/features/workout/ without duplicating it.
//
// Sourced from docs/test-plan-2026-06-16.md (Módulo: workout). Each test maps
// to a P0/P1 (and one notable P2) AUTOMATABLE case that was NOT yet covered by
// the existing tests as of 2026-06-16:
//
//   workout-40 — repsDisplayText: 'Al fallo' / MM:SS / 'min–max reps' branches
//                (the whole helper was untested).
//   workout-39 — plannedRepsForSpec: repsMin-only fallback path (only reps /
//                repsMax / duration were covered in session_player_screen_test).
//   workout-38 — isSupersetBlockComplete: every member must meet its week set
//                count (only isStandaloneBlockComplete was tested directly).
//   workout-49 — SessionNotifier.updateSet throws when SetLog id is empty.
//   workout-50 — SessionNotifier.updateSet overwrites the matching log in place
//                (same list size, same id, repo.updateSetLog called once).
//   workout-20 — parseReps('-5'): negative input is rejected → [] (the leading
//                minus is no longer swallowed as a separator). Fixed in the
//                2026-06-16 audit follow-up; the test is now active.
//
// Conventions mirror session_notifier_test.dart (mocktail, ProviderContainer
// overrides, stub_factories helpers) and session_player_screen_test.dart
// (top-level block/spec helpers imported from the screen file).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_init.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/reps_format.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/set_enums.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/domain/set_spec.dart';
import 'package:treino/features/workout/presentation/session_player_screen.dart';

import '../../helpers/fake_analytics_service.dart';
import 'application/stub_factories.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockSessionRepository extends Mock implements SessionRepository {}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Mirrors session_notifier_test.dart::_makeContainer.
ProviderContainer _makeContainer({
  required MockSessionRepository repo,
  required String uid,
  Routine? routine,
}) {
  return ProviderContainer(
    overrides: [
      sessionRepositoryProvider.overrideWithValue(repo),
      currentUidProvider.overrideWithValue(uid),
      analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
      if (routine != null)
        routineByIdProvider(routine.id).overrideWith(
          (ref) async => routine,
        ),
    ],
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(makeSession());
    registerFallbackValue(makeSetLog());
  });

  // ── workout-40 — repsDisplayText branches ──────────────────────────────────
  group('workout-40: repsDisplayText', () {
    test('failure set shows "Al fallo" regardless of reps/mode', () {
      const spec = SetSpec(type: SetType.failure, reps: 8);
      expect(repsDisplayText(spec, ExerciseMode.reps), 'Al fallo');
    });

    test('duration set renders MM:SS (90s → 01:30)', () {
      const spec = SetSpec(durationSeconds: 90);
      expect(repsDisplayText(spec, ExerciseMode.duration), '01:30');
    });

    test('range set renders "min–max reps" with en-dash', () {
      const spec = SetSpec(repsMin: 8, repsMax: 12);
      expect(repsDisplayText(spec, ExerciseMode.reps), '8–12 reps');
    });

    test('single reps set renders "N reps"', () {
      const spec = SetSpec(reps: 10);
      expect(repsDisplayText(spec, ExerciseMode.reps), '10 reps');
    });
  });

  // ── workout-39 — plannedRepsForSpec repsMin-only fallback ──────────────────
  group('workout-39: plannedRepsForSpec', () {
    test('repsMin-only spec falls back to repsMin when reps/repsMax are null',
        () {
      const spec = SetSpec(repsMin: 8);
      expect(plannedRepsForSpec(spec, ExerciseMode.reps), 8);
    });

    test('range spec uses repsMax (top of range)', () {
      const spec = SetSpec(repsMin: 8, repsMax: 12);
      expect(plannedRepsForSpec(spec, ExerciseMode.reps), 12);
    });

    test('duration mode always returns 0 even with reps populated', () {
      const spec = SetSpec(reps: 10);
      expect(plannedRepsForSpec(spec, ExerciseMode.duration), 0);
    });
  });

  // ── workout-38 — isSupersetBlockComplete ───────────────────────────────────
  group('workout-38: isSupersetBlockComplete', () {
    final slotA = makeSlot(exerciseId: 'a', targetSets: 2);
    final slotB = makeSlot(exerciseId: 'b', targetSets: 2);

    test('incomplete when one member has fewer logs than its week set count',
        () {
      final logs = <SetLog>[
        makeSetLog(exerciseId: 'a', setNumber: 1),
        makeSetLog(exerciseId: 'a', setNumber: 2),
        makeSetLog(exerciseId: 'b', setNumber: 1), // only 1 of 2 for b
      ];
      expect(isSupersetBlockComplete([slotA, slotB], logs, 0), isFalse);
    });

    test('complete once every member meets its week set count', () {
      final logs = <SetLog>[
        makeSetLog(exerciseId: 'a', setNumber: 1),
        makeSetLog(exerciseId: 'a', setNumber: 2),
        makeSetLog(exerciseId: 'b', setNumber: 1),
        makeSetLog(exerciseId: 'b', setNumber: 2),
      ];
      expect(isSupersetBlockComplete([slotA, slotB], logs, 0), isTrue);
    });
  });

  // ── workout-49 — updateSet throws on empty id ──────────────────────────────
  group('workout-49: SessionNotifier.updateSet rejects empty SetLog id',
      () {
    test('throws StateError and does NOT write to Firestore', () async {
      final repo = MockSessionRepository();
      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
          )).thenAnswer((_) async => makeSession());
      when(() => repo.updateSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).thenAnswer((_) async {});

      final routine = makeRoutine();
      final container = _makeContainer(repo: repo, uid: 'u1', routine: routine);
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      await container.read(sessionNotifierProvider(init).future);
      final notifier = container.read(sessionNotifierProvider(init).notifier);

      await expectLater(
        () => notifier.updateSet(makeSetLog(id: '')),
        throwsA(isA<StateError>()),
      );

      verifyNever(() => repo.updateSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          ));
    });
  });

  // ── workout-50 — updateSet overwrites matching log in place ────────────────
  group('workout-50: SessionNotifier.updateSet overwrites matching log', () {
    test('replaces the log with the same id; list size unchanged; repo once',
        () async {
      final repo = MockSessionRepository();
      when(() => repo.create(
            uid: any(named: 'uid'),
            routineId: any(named: 'routineId'),
            routineName: any(named: 'routineName'),
            startedAt: any(named: 'startedAt'),
            dayNumber: any(named: 'dayNumber'),
          )).thenAnswer((_) async => makeSession());
      // addSetLog returns the SetLog it was given (so the persisted id is kept).
      when(() => repo.addSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).thenAnswer(
        (inv) async => inv.namedArguments[const Symbol('setLog')] as SetLog,
      );
      when(() => repo.updateSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).thenAnswer((_) async {});

      final routine = makeRoutine();
      final container = _makeContainer(repo: repo, uid: 'u1', routine: routine);
      addTearDown(container.dispose);

      final init = FreshSession(routineId: routine.id, dayNumber: 1);
      await container.read(sessionNotifierProvider(init).future);
      final notifier = container.read(sessionNotifierProvider(init).notifier);

      // Seed a persisted log id='abc' at 40kg.
      await notifier.logSet(
        makeSetLog(id: 'abc', exerciseId: 'e1', setNumber: 1, weightKg: 40),
      );
      final before = container.read(sessionNotifierProvider(init)).value!;
      expect(before.setLogs, hasLength(1));

      // Update the same log to 50kg.
      await notifier.updateSet(
        makeSetLog(id: 'abc', exerciseId: 'e1', setNumber: 1, weightKg: 50),
      );

      final after = container.read(sessionNotifierProvider(init)).value!;
      expect(after.setLogs, hasLength(1),
          reason: 'updateSet must not append a new row');
      final updated = after.setLogs.single;
      expect(updated.id, 'abc');
      expect(updated.weightKg, 50);

      verify(() => repo.updateSetLog(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
            setLog: any(named: 'setLog'),
          )).called(1);
    });
  });

  // ── workout-20 — parseReps rejects negative input ──────────────────────────
  group('workout-20: parseReps negative input', () {
    test(
      'parseReps("-5") rejects negative input → []',
      () {
        // CORRECT behavior: a leading minus marks the input invalid (negative
        // reps make no sense), so the whole string is rejected.
        expect(parseReps('-5'), equals(<int>[]));
      },
    );
  });
}
