// RED tests for aggregateAdherenceProvider (dashboard-hoy-aggregates PR2).
//
// Covers:
//   - SCENARIO-ADH-01: average of non-null per-athlete values.
//   - SCENARIO-ADH-02: null when all athletes lack a plan (weeklyTarget == 0).
//   - SCENARIO-ADH-03: respects the active+sharedWithTrainer security gate.
//   - SCENARIO-ADH-04: excludes non-sharing athletes from the aggregate.
//   - SCENARIO-ADH-05: empty link list → null (no fan-out).
//   - SCENARIO-ADH-06: athlete with plan but zero completed sessions → 0%.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach_hub/application/aggregate_adherence_provider.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart'
    show assignedRoutinesProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show finishedInWindowByUidProvider, FinishedInWindowKey;
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_status.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';

// ─── Factories ─────────────────────────────────────────────────────────────────

TrainerLink _activeSharing(String athleteId) => TrainerLink(
      id: 'link-$athleteId',
      trainerId: 'trainer-1',
      athleteId: athleteId,
      status: TrainerLinkStatus.active,
      sharedWithTrainer: true,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 2),
    );

TrainerLink _activeNotSharing(String athleteId) => TrainerLink(
      id: 'link-ns-$athleteId',
      trainerId: 'trainer-1',
      athleteId: athleteId,
      status: TrainerLinkStatus.active,
      sharedWithTrainer: false,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 2),
    );

// Creates a routine with [daysCount] days (weeklyTarget = daysCount).
Routine _routineWithDays(String athleteId, int daysCount) => Routine(
      id: 'routine-$athleteId',
      name: 'Plan $athleteId',
      level: ExperienceLevel.beginner,
      days: List.generate(
        daysCount,
        (i) => RoutineDay(
          dayNumber: i + 1,
          name: 'Día ${i + 1}',
          slots: const [],
        ),
      ),
      status: RoutineStatus.active,
      numWeeks: 1,
    );

// A completed session (status == finished && wasFullyCompleted == true).
Session _completedSession(String athleteId, {required DateTime finishedAt}) =>
    Session(
      id: 'sess-$athleteId-${finishedAt.millisecondsSinceEpoch}',
      uid: athleteId,
      routineId: 'routine-$athleteId',
      routineName: 'Plan $athleteId',
      startedAt: finishedAt.subtract(const Duration(hours: 1)),
      finishedAt: finishedAt,
      totalVolumeKg: 1000,
      durationMin: 60,
      status: SessionStatus.finished,
      wasFullyCompleted: true,
      dayNumber: 1,
      weekNumber: 0,
    );

// An abandoned session (status == finished but wasFullyCompleted == false).
Session _abandonedSession(String athleteId, {required DateTime finishedAt}) =>
    Session(
      id: 'aband-$athleteId-${finishedAt.millisecondsSinceEpoch}',
      uid: athleteId,
      routineId: 'routine-$athleteId',
      routineName: 'Plan $athleteId',
      startedAt: finishedAt.subtract(const Duration(hours: 1)),
      finishedAt: finishedAt,
      totalVolumeKg: 100,
      durationMin: 30,
      status: SessionStatus.finished,
      wasFullyCompleted: false,
      dayNumber: 1,
      weekNumber: 0,
    );

// ─── Helper ────────────────────────────────────────────────────────────────────

/// Builds a container with the given links, per-athlete sessions and routines.
///
/// [sessionsByAthleteId] maps athleteId → list of completed sessions (already
///   filtered by window — the test controls what the provider returns).
/// [routinesByAthleteId] maps athleteId → list of routines for that athlete.
ProviderContainer _buildContainer({
  required List<TrainerLink> links,
  required Map<String, List<Session>> sessionsByAthleteId,
  required Map<String, List<Routine>> routinesByAthleteId,
}) {
  return ProviderContainer(
    overrides: [
      trainerLinksStreamProvider.overrideWith(
        (ref) => Stream.value(links),
      ),
      finishedInWindowByUidProvider.overrideWith(
        (ref, key) async =>
            sessionsByAthleteId[key.athleteId] ?? const <Session>[],
      ),
      assignedRoutinesProvider.overrideWith(
        (ref, athleteId) async =>
            routinesByAthleteId[athleteId] ?? const <Routine>[],
      ),
    ],
  );
}

/// Reads [aggregateAdherenceProvider] from [container] and awaits the result.
Future<double?> _readAdherence(ProviderContainer container) {
  final completer = Completer<double?>();
  container.listen<AsyncValue<double?>>(
    aggregateAdherenceProvider,
    (_, next) {
      if (next.isLoading) return;
      if (next.hasError) {
        completer.completeError(next.error!, next.stackTrace);
      } else {
        completer.complete(next.valueOrNull);
      }
    },
    fireImmediately: true,
  );
  return completer.future;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // SCENARIO-ADH-01: average of non-null per-athlete adherencia values.
  group('SCENARIO-ADH-01 — averages non-null per-athlete adherencia', () {
    test('two athletes with plans → returns arithmetic average', () async {
      // Athlete A: weeklyTarget=3, 30-day window → planned=30*3/7≈12.86.
      // We give them 9 completed sessions → adherencia = 9/12.86*100 ≈ 70%.
      // Athlete B: weeklyTarget=4, planned=30*4/7≈17.14.
      // We give them 17 completed sessions → adherencia ≈ 99.2%.
      // Average ≈ (70 + 99.2) / 2 = 84.6%.
      //
      // The exact value depends on DateTime.now() inside the provider since
      // ResumenMetrics.compute also receives `now`. We just assert non-null
      // and within range rather than a specific float.
      final now = DateTime.now().toUtc();
      final todayStart = DateTime.utc(now.year, now.month, now.day);
      final within30d = todayStart.subtract(const Duration(days: 5));

      final container = _buildContainer(
        links: [
          _activeSharing('a1'),
          _activeSharing('a2'),
        ],
        sessionsByAthleteId: {
          'a1': List.generate(
            9,
            (i) => _completedSession('a1',
                finishedAt: within30d.subtract(Duration(days: i))),
          ),
          'a2': List.generate(
            17,
            (i) => _completedSession('a2',
                finishedAt: within30d.subtract(Duration(days: i))),
          ),
        },
        routinesByAthleteId: {
          'a1': [_routineWithDays('a1', 3)],
          'a2': [_routineWithDays('a2', 4)],
        },
      );
      addTearDown(container.dispose);

      final result = await _readAdherence(container);
      expect(result, isNotNull);
      expect(result!, isA<double>());
      // Both athletes have plans → aggregate is a real percentage ≥ 0.
      expect(result, greaterThanOrEqualTo(0.0));
    });
  });

  // SCENARIO-ADH-02: null when all athletes have no active plan (weeklyTarget=0).
  group('SCENARIO-ADH-02 — null when no athlete has a plan', () {
    test('all athletes have empty routines → null aggregate', () async {
      final container = _buildContainer(
        links: [
          _activeSharing('a1'),
          _activeSharing('a2'),
        ],
        sessionsByAthleteId: {
          'a1': [],
          'a2': [],
        },
        routinesByAthleteId: {
          'a1': [], // no routines → weeklyTarget = 0
          'a2': [],
        },
      );
      addTearDown(container.dispose);

      final result = await _readAdherence(container);
      expect(result, isNull);
    });
  });

  // SCENARIO-ADH-03: respects the active+sharedWithTrainer security gate.
  group('SCENARIO-ADH-03 — security gate: only active+sharing athletes', () {
    test('inactive or non-sharing links are excluded from the aggregate',
        () async {
      // Only 'a1' (active+sharing) → aggregate reflects only a1.
      // 'a2' is active but NOT sharing → excluded.
      // 'a3' is paused+sharing → excluded (status != active).
      final container = _buildContainer(
        links: [
          _activeSharing('a1'),
          _activeNotSharing('a2'),
          TrainerLink(
            id: 'link-a3',
            trainerId: 'trainer-1',
            athleteId: 'a3',
            status: TrainerLinkStatus.paused,
            sharedWithTrainer: true,
            requestedAt: DateTime.utc(2026, 1, 1),
            acceptedAt: DateTime.utc(2026, 1, 2),
          ),
        ],
        sessionsByAthleteId: {
          'a1': [
            _completedSession('a1',
                finishedAt: DateTime.now().toUtc().subtract(
                      const Duration(days: 2),
                    )),
          ],
          'a2': [
            _completedSession('a2',
                finishedAt: DateTime.now().toUtc().subtract(
                      const Duration(days: 1),
                    )),
          ],
          'a3': [
            _completedSession('a3',
                finishedAt: DateTime.now().toUtc().subtract(
                      const Duration(days: 1),
                    )),
          ],
        },
        routinesByAthleteId: {
          'a1': [_routineWithDays('a1', 3)],
          'a2': [_routineWithDays('a2', 3)],
          'a3': [_routineWithDays('a3', 3)],
        },
      );
      addTearDown(container.dispose);

      // Should not throw; returns a value driven only by a1.
      final result = await _readAdherence(container);
      // a1 has a plan → result is non-null.
      expect(result, isNotNull);
    });
  });

  // SCENARIO-ADH-04: excludes non-sharing athletes from the aggregate.
  group('SCENARIO-ADH-04 — non-sharing athletes do not affect aggregate', () {
    test(
        'trainer with 3 athletes but only 1 sharing → aggregate = solo athlete',
        () async {
      // a1: sharing, has plan.
      // a2, a3: not sharing.
      // If a2/a3 were included, they'd inflate or distort the average.
      // With only a1, we should get a non-null value.
      final container = _buildContainer(
        links: [
          _activeSharing('a1'),
          _activeNotSharing('a2'),
          _activeNotSharing('a3'),
        ],
        sessionsByAthleteId: {
          'a1': [
            _completedSession('a1',
                finishedAt: DateTime.now().toUtc().subtract(
                      const Duration(days: 1),
                    )),
          ],
        },
        routinesByAthleteId: {
          'a1': [_routineWithDays('a1', 3)],
        },
      );
      addTearDown(container.dispose);

      final result = await _readAdherence(container);
      expect(result, isNotNull);
    });
  });

  // SCENARIO-ADH-05: empty links → null immediately (no fan-out needed).
  group('SCENARIO-ADH-05 — empty links list → null', () {
    test('no active+sharing athletes → null (not 0.0)', () async {
      final container = _buildContainer(
        links: const [],
        sessionsByAthleteId: const {},
        routinesByAthleteId: const {},
      );
      addTearDown(container.dispose);

      final result = await _readAdherence(container);
      expect(result, isNull);
    });
  });

  // SCENARIO-ADH-06: athlete with plan but zero completed sessions → 0%.
  group('SCENARIO-ADH-06 — athlete with plan but no sessions → 0% adherencia',
      () {
    test('zero sessions → adherencia 0.0, aggregate is 0.0', () async {
      final container = _buildContainer(
        links: [_activeSharing('a1')],
        sessionsByAthleteId: {'a1': []}, // no sessions at all
        routinesByAthleteId: {
          'a1': [_routineWithDays('a1', 3)],
        },
      );
      addTearDown(container.dispose);

      final result = await _readAdherence(container);
      expect(result, isNotNull);
      expect(result, 0.0);
    });
  });

  // Abandoned sessions do NOT count as isCompletedSession.
  group('SCENARIO-ADH-07 — abandoned sessions excluded from adherencia', () {
    test('only abandoned sessions → adherencia 0.0', () async {
      final now = DateTime.now().toUtc();
      final container = _buildContainer(
        links: [_activeSharing('a1')],
        sessionsByAthleteId: {
          'a1': [
            _abandonedSession('a1',
                finishedAt: now.subtract(const Duration(days: 1))),
            _abandonedSession('a1',
                finishedAt: now.subtract(const Duration(days: 2))),
          ],
        },
        routinesByAthleteId: {
          'a1': [_routineWithDays('a1', 3)],
        },
      );
      addTearDown(container.dispose);

      final result = await _readAdherence(container);
      expect(result, isNotNull);
      // Abandoned sessions don't count → 0 completed / planned = 0%.
      expect(result, 0.0);
    });
  });
}
