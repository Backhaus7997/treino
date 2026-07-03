// RED tests for inactivosProvider.
// Verifies the fan-out logic against ProviderContainer overrides.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach_hub/application/inactivos_provider.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show finishedInWindowByUidProvider, FinishedInWindowKey;
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

Session _finishedSession(String athleteId) => Session(
      id: 'session-$athleteId',
      uid: athleteId,
      routineId: 'r1',
      routineName: 'Rutina',
      startedAt: DateTime.utc(2026, 6, 10, 10, 0),
      finishedAt: DateTime.utc(2026, 6, 10, 11, 0),
      totalVolumeKg: 1000,
      durationMin: 60,
      status: SessionStatus.finished,
      dayNumber: 1,
      weekNumber: 0,
    );

// ─── Helper ────────────────────────────────────────────────────────────────────

/// Builds a ProviderContainer with the given link list and per-athlete session
/// overrides. The window key is the same day-truncated one the provider uses.
ProviderContainer _buildContainer({
  required List<TrainerLink> links,
  required Map<String, List<Session>> sessionsByAthleteId,
}) {
  // The inactivos provider uses todayStart (day-truncated) as base.
  // We override finishedInWindowByUidProvider for all athlete keys.
  final overrides = <Override>[
    trainerLinksStreamProvider.overrideWith(
      (ref) => Stream.value(links),
    ),
    // Override the entire family to map athleteId → session list.
    finishedInWindowByUidProvider.overrideWith(
      (ref, key) async =>
          sessionsByAthleteId[key.athleteId] ?? const <Session>[],
    ),
  ];
  return ProviderContainer(overrides: overrides);
}

/// Reads [inactivosProvider] while keeping it alive (listen keeps autoDispose
/// from garbage-collecting the provider before the Future resolves).
Future<InactivosResult> _readInactivos(ProviderContainer container) {
  final completer = Completer<InactivosResult>();
  container.listen<AsyncValue<InactivosResult>>(
    inactivosProvider,
    (prev, next) {
      next.whenOrNull(
        data: (d) {
          if (!completer.isCompleted) completer.complete(d);
        },
        error: (e, st) {
          if (!completer.isCompleted) completer.completeError(e, st);
        },
      );
    },
    fireImmediately: true,
  );
  return completer.future;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('inactivosProvider', () {
    test('athlete with no session in window is inactive', () async {
      final container = _buildContainer(
        links: [_activeSharing('a1'), _activeSharing('a2')],
        sessionsByAthleteId: {
          'a1': [], // no sessions → inactive
          'a2': [_finishedSession('a2')], // has a session → active
        },
      );
      addTearDown(container.dispose);

      final result =
          await _readInactivos(container);

      expect(result.inactiveAthleteIds, contains('a1'));
      expect(result.inactiveAthleteIds, isNot(contains('a2')));
    });

    test('count matches number of inactive athletes', () async {
      final container = _buildContainer(
        links: [
          _activeSharing('a1'),
          _activeSharing('a2'),
          _activeSharing('a3'),
        ],
        sessionsByAthleteId: {
          'a1': [],
          'a2': [],
          'a3': [_finishedSession('a3')],
        },
      );
      addTearDown(container.dispose);

      final result = await _readInactivos(container);

      expect(result.inactiveCount, 2);
      expect(result.totalSharingCount, 3);
    });

    test('athletes not sharing are excluded (security gate)', () async {
      final container = _buildContainer(
        links: [
          _activeSharing('a1'),
          _activeNotSharing('a2'), // not sharing — invisible
        ],
        sessionsByAthleteId: {
          'a1': [],
          'a2': [],
        },
      );
      addTearDown(container.dispose);

      final result = await _readInactivos(container);

      // a2 is not sharing → not counted in totalSharingCount or inactivos
      expect(result.totalSharingCount, 1);
      expect(result.inactiveAthleteIds, contains('a1'));
      expect(result.inactiveAthleteIds, isNot(contains('a2')));
    });

    test('empty list when all athletes trained recently', () async {
      final container = _buildContainer(
        links: [_activeSharing('a1'), _activeSharing('a2')],
        sessionsByAthleteId: {
          'a1': [_finishedSession('a1')],
          'a2': [_finishedSession('a2')],
        },
      );
      addTearDown(container.dispose);

      final result = await _readInactivos(container);

      expect(result.inactiveAthleteIds, isEmpty);
      expect(result.inactiveCount, 0);
    });

    test('no active+sharing links → empty result', () async {
      final container = _buildContainer(
        links: const [],
        sessionsByAthleteId: const {},
      );
      addTearDown(container.dispose);

      final result = await _readInactivos(container);

      expect(result.inactiveAthleteIds, isEmpty);
      expect(result.totalSharingCount, 0);
    });
  });
}
