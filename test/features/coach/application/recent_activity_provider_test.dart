// Tests for recentActivityProvider (trainer dashboard "Actividad reciente").
//
// Fans out over active links and reads each athlete's finished sessions in the
// recent ART window via finishedInWindowByUidProvider. Access is gated by
// session_shares at the rules layer, so non-sharing athletes surface as
// permission-denied and are skipped. The feed is newest-first, capped at 8.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/recent_activity_provider.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show finishedInWindowByUidProvider;
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';

// ─── Factories ───────────────────────────────────────────────────────────────

TrainerLink _link(
  String athleteId, {
  TrainerLinkStatus status = TrainerLinkStatus.active,
}) =>
    TrainerLink(
      id: 'link-$athleteId',
      trainerId: 'trainer-1',
      athleteId: athleteId,
      status: status,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 2),
    );

Session _session(String id, {required DateTime finishedAt}) => Session(
      id: id,
      uid: 'a',
      routineId: 'r1',
      routineName: 'Rutina',
      startedAt: finishedAt,
      finishedAt: finishedAt,
      status: SessionStatus.finished,
      wasFullyCompleted: true,
    );

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Overrides the window family by athleteId (ignores the computed from/to), or
/// throws for ids in [denied] to simulate a session_shares permission-denied.
ProviderContainer _buildContainer({
  required List<TrainerLink> links,
  required Map<String, List<Session>> sessionsByAthleteId,
  Set<String> denied = const {},
}) {
  return ProviderContainer(overrides: [
    trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
    finishedInWindowByUidProvider.overrideWith((ref, key) async {
      if (denied.contains(key.athleteId)) {
        throw Exception('permission-denied');
      }
      return sessionsByAthleteId[key.athleteId] ?? const <Session>[];
    }),
  ]);
}

Future<List<RecentActivityEntry>> _read(ProviderContainer container) {
  final completer = Completer<List<RecentActivityEntry>>();
  container.listen<AsyncValue<List<RecentActivityEntry>>>(
    recentActivityProvider,
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

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('recentActivityProvider', () {
    test("aggregates active athletes' sessions, newest-first", () async {
      final container = _buildContainer(
        links: [_link('a1'), _link('a2')],
        sessionsByAthleteId: {
          'a1': [_session('s-old', finishedAt: DateTime.utc(2026, 6, 10))],
          'a2': [_session('s-new', finishedAt: DateTime.utc(2026, 6, 12))],
        },
      );
      addTearDown(container.dispose);

      final entries = await _read(container);

      expect(entries.map((e) => e.session.id), ['s-new', 's-old']);
    });

    test('non-active (pending) link is excluded', () async {
      final container = _buildContainer(
        links: [_link('a1'), _link('a2', status: TrainerLinkStatus.pending)],
        sessionsByAthleteId: {
          'a1': [_session('s1', finishedAt: DateTime.utc(2026, 6, 10))],
          'a2': [_session('s2', finishedAt: DateTime.utc(2026, 6, 11))],
        },
      );
      addTearDown(container.dispose);

      final entries = await _read(container);

      expect(entries.map((e) => e.athleteId), ['a1']);
    });

    test('athlete whose session read is denied is skipped', () async {
      final container = _buildContainer(
        links: [_link('a1'), _link('a2')],
        sessionsByAthleteId: {
          'a1': [_session('s1', finishedAt: DateTime.utc(2026, 6, 10))],
        },
        denied: {'a2'},
      );
      addTearDown(container.dispose);

      final entries = await _read(container);

      expect(entries.map((e) => e.athleteId), ['a1']);
    });

    test('caps the feed at 8 entries (newest kept)', () async {
      final many = [
        for (int i = 0; i < 12; i++)
          _session('s$i',
              finishedAt: DateTime.utc(2026, 6, 1).add(Duration(hours: i))),
      ];
      final container = _buildContainer(
        links: [_link('a1')],
        sessionsByAthleteId: {'a1': many},
      );
      addTearDown(container.dispose);

      final entries = await _read(container);

      expect(entries.length, 8);
      expect(entries.first.session.id, 's11'); // latest
    });

    test('no active links → empty', () async {
      final container = _buildContainer(
        links: const [],
        sessionsByAthleteId: const {},
      );
      addTearDown(container.dispose);

      final entries = await _read(container);

      expect(entries, isEmpty);
    });
  });
}
