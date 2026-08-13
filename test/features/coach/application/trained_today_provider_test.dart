// Tests for trainedTodayProvider (mobile "Entrenaron hoy").
//
// Gate change (dead sharedWithTrainer): the gate is now `status == active`
// only. setSharedWithTrainer has zero callers, so the flag was always false —
// the old `&& sharedWithTrainer == true` predicate made this list PERMANENTLY
// empty (a dead feature). Per-athlete session access is authorised at the rules
// layer via session_shares (CF-written on `status === 'active'`), NOT by this
// flag; non-sharing athletes surface as permission-denied and are skipped.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/trained_today_provider.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show finishedTodayByUidProvider;
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';

// ─── Factories ───────────────────────────────────────────────────────────────

TrainerLink _link(
  String athleteId, {
  TrainerLinkStatus status = TrainerLinkStatus.active,
  bool sharedWithTrainer = false,
}) =>
    TrainerLink(
      id: 'link-$athleteId',
      trainerId: 'trainer-1',
      athleteId: athleteId,
      status: status,
      sharedWithTrainer: sharedWithTrainer,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 2),
    );

/// A finished session stamped NOW so it lands on today's UTC calendar day (the
/// provider re-checks the day defensively against DateTime.now()).
Session _todaySession(String athleteId) {
  final now = DateTime.now().toUtc();
  return Session(
    id: 'session-$athleteId',
    uid: athleteId,
    routineId: 'r1',
    routineName: 'Rutina',
    startedAt: now,
    finishedAt: now,
    status: SessionStatus.finished,
    wasFullyCompleted: true,
  );
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

ProviderContainer _buildContainer({
  required List<TrainerLink> links,
  required Map<String, List<Session>> sessionsByAthleteId,
  Set<String> denied = const {},
  Set<String> failed = const {},
}) {
  return ProviderContainer(overrides: [
    trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
    // denied → session_shares permission-denied (expected opt-out).
    // failed → a real backend error (e.g. missing index, unavailable).
    finishedTodayByUidProvider.overrideWith((ref, uid) async {
      if (denied.contains(uid)) {
        throw FirebaseException(
            plugin: 'cloud_firestore', code: 'permission-denied');
      }
      if (failed.contains(uid)) {
        throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
      }
      return sessionsByAthleteId[uid] ?? const <Session>[];
    }),
  ]);
}

/// Reads [trainedTodayProvider], keeping it alive until it settles to data.
Future<List<TrainedTodayEntry>> _read(ProviderContainer container) {
  final completer = Completer<List<TrainedTodayEntry>>();
  container.listen<AsyncValue<List<TrainedTodayEntry>>>(
    trainedTodayProvider,
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
  group('trainedTodayProvider', () {
    test('active link + finished-today session → athlete appears', () async {
      final container = _buildContainer(
        links: [_link('a1', sharedWithTrainer: true)],
        sessionsByAthleteId: {
          'a1': [_todaySession('a1')],
        },
      );
      addTearDown(container.dispose);

      final entries = await _read(container);

      expect(entries.map((e) => e.athleteId), contains('a1'));
    });

    // Bug fix (abandoned-session-streak-reports): abandonSession() saves
    // status=finished with wasFullyCompleted=false — an abandon today must
    // NOT make the athlete appear in "Entrenaron hoy".
    test("today's abandoned session does NOT count as trained today", () async {
      final now = DateTime.now().toUtc();
      final abandonedToday = Session(
        id: 'abandoned-a1',
        uid: 'a1',
        routineId: 'r1',
        routineName: 'Rutina',
        startedAt: now,
        finishedAt: now,
        status: SessionStatus.finished,
        wasFullyCompleted: false,
      );
      final container = _buildContainer(
        links: [_link('a1', sharedWithTrainer: true)],
        sessionsByAthleteId: {
          'a1': [abandonedToday],
        },
      );
      addTearDown(container.dispose);

      final entries = await _read(container);

      expect(entries.map((e) => e.athleteId), isNot(contains('a1')));
    });

    // Regression for the dead gate: an active athlete with sharedWithTrainer
    // false (the always-false default) MUST still appear — the old predicate
    // excluded them, which killed the whole list.
    test('active + sharedWithTrainer==false still appears (gate fix)',
        () async {
      final container = _buildContainer(
        links: [_link('a1', sharedWithTrainer: false)],
        sessionsByAthleteId: {
          'a1': [_todaySession('a1')],
        },
      );
      addTearDown(container.dispose);

      final entries = await _read(container);

      expect(entries.map((e) => e.athleteId), contains('a1'));
    });

    test('athlete whose session read is denied is skipped, no crash', () async {
      final container = _buildContainer(
        links: [_link('a1', sharedWithTrainer: true), _link('a2')],
        sessionsByAthleteId: {
          'a1': [_todaySession('a1')],
        },
        denied: {'a2'}, // a2 not sharing → read denied
      );
      addTearDown(container.dispose);

      final entries = await _read(container);
      final ids = entries.map((e) => e.athleteId).toList();

      expect(ids, contains('a1'));
      expect(ids, isNot(contains('a2')));
    });

    test('non-active (pending) link is excluded', () async {
      final container = _buildContainer(
        links: [
          _link('a1', sharedWithTrainer: true),
          _link('a2', status: TrainerLinkStatus.pending),
        ],
        sessionsByAthleteId: {
          'a1': [_todaySession('a1')],
          'a2': [_todaySession('a2')],
        },
      );
      addTearDown(container.dispose);

      final entries = await _read(container);
      final ids = entries.map((e) => e.athleteId).toList();

      expect(ids, contains('a1'));
      expect(ids, isNot(contains('a2')));
    });

    // ── M1: don't render a total read failure as a false "nobody trained" ──

    // A real (non-permission-denied) failure on EVERY athlete must surface as
    // an error, not the misleading empty state that hides a broken query.
    test('all reads fail with a backend error → provider surfaces error',
        () async {
      final container = _buildContainer(
        links: [_link('a1'), _link('a2')],
        sessionsByAthleteId: const {},
        failed: {'a1', 'a2'},
      );
      addTearDown(container.dispose);

      await expectLater(
        _read(container),
        throwsA(isA<FirebaseException>()
            .having((e) => e.code, 'code', 'unavailable')),
      );
    });

    // A backend failure on one athlete must NOT hide those who did train: a
    // partial result stays data, never an error.
    test('backend error on one athlete but another has data → data (partial)',
        () async {
      final container = _buildContainer(
        links: [_link('a1'), _link('a2')],
        sessionsByAthleteId: {
          'a1': [_todaySession('a1')],
        },
        failed: {'a2'},
      );
      addTearDown(container.dispose);

      final entries = await _read(container);

      expect(entries.map((e) => e.athleteId), ['a1']);
    });

    // permission-denied is the expected opt-out signal: all-denied stays empty
    // DATA (not an error), so trainers whose athletes don't share sessions keep
    // seeing the honest "nobody trained" empty state.
    test('all reads denied (opt-out) → empty data, not an error', () async {
      final container = _buildContainer(
        links: [_link('a1'), _link('a2')],
        sessionsByAthleteId: const {},
        denied: {'a1', 'a2'},
      );
      addTearDown(container.dispose);

      final entries = await _read(container);

      expect(entries, isEmpty);
    });
  });
}
