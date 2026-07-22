import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/core/utils/argentina_time.dart';
import 'package:treino/features/insights/application/insights_providers.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/session_status.dart';

import '../../workout/application/stub_factories.dart';

class MockSessionRepository extends Mock implements SessionRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(makeSession());
    registerFallbackValue(makeSetLog());
  });

  // Helper: build a ProviderContainer with a mock repo returning [sessions].
  // routineByIdProvider is overridden for any routineId to return null,
  // avoiding Firebase dependencies in these focused unit tests.
  ProviderContainer makeContainer({
    required MockSessionRepository repo,
    String uid = 'u1',
  }) {
    return ProviderContainer(overrides: [
      currentUidProvider.overrideWithValue(uid),
      sessionRepositoryProvider.overrideWithValue(repo),
      exercisesProvider.overrideWith((ref) async => const <Exercise>[]),
      routineByIdProvider('r1').overrideWith((ref) async => null),
      visibleRoutineByIdProvider('r1').overrideWith((ref) async => null),
    ]);
  }

  group('weeklyInsightsProvider — streak (SCENARIO-300..303)', () {
    // SCENARIO-300: trained today → streak includes today + preceding consecutive days
    test('SCENARIO-300: trained today → streak ≥ 1', () async {
      final repo = MockSessionRepository();
      // computeStreak buckets by the Argentina calendar day (#411). Anchor
      // fixtures to `argentinaNow()` and make them UTC-flagged at noon UTC
      // (= 09:00 ART, same ART day under any runner, never crosses midnight),
      // mirroring real data (always UTC-flagged via TimestampConverter). A
      // device-local fixture would flake near the ART midnight boundary.
      final nowArt = argentinaNow();
      final today = DateTime.utc(nowArt.year, nowArt.month, nowArt.day, 12);
      final yesterday = today.subtract(const Duration(days: 1));

      when(() => repo.listByUid('u1')).thenAnswer((_) async => [
            makeSession(
              id: 's1',
              startedAt: today,
              status: SessionStatus.finished,
              wasFullyCompleted: true,
            ),
            makeSession(
              id: 's2',
              startedAt: yesterday,
              status: SessionStatus.finished,
              wasFullyCompleted: true,
            ),
          ]);
      when(() => repo.listSetLogs(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
          )).thenAnswer((_) async => []);

      final container = makeContainer(repo: repo);
      addTearDown(container.dispose);

      final result = await container.read(weeklyInsightsProvider.future);
      // Trained today + yesterday = streak of at least 2
      expect(result!.streak, greaterThanOrEqualTo(2));
    });

    // SCENARIO-301: not trained today → streak counts from yesterday backwards
    test('SCENARIO-301: not trained today → streak counts from yesterday',
        () async {
      final repo = MockSessionRepository();
      // UTC-flagged noon anchors on consecutive ART days (see SCENARIO-300).
      final nowArt = argentinaNow();
      final today = DateTime.utc(nowArt.year, nowArt.month, nowArt.day, 12);
      final yesterday = today.subtract(const Duration(days: 1));
      final dayBefore = today.subtract(const Duration(days: 2));

      when(() => repo.listByUid('u1')).thenAnswer((_) async => [
            makeSession(
              id: 's1',
              startedAt: yesterday,
              status: SessionStatus.finished,
              wasFullyCompleted: true,
            ),
            makeSession(
              id: 's2',
              startedAt: dayBefore,
              status: SessionStatus.finished,
              wasFullyCompleted: true,
            ),
          ]);
      when(() => repo.listSetLogs(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
          )).thenAnswer((_) async => []);

      final container = makeContainer(repo: repo);
      addTearDown(container.dispose);

      final result = await container.read(weeklyInsightsProvider.future);
      expect(result!.streak, 2);
    });

    // SCENARIO-302: gap breaks the streak
    test('SCENARIO-302: gap in consecutive days → shorter streak', () async {
      final repo = MockSessionRepository();
      // UTC-flagged noon anchors on ART days (see SCENARIO-300).
      final nowArt = argentinaNow();
      final today = DateTime.utc(nowArt.year, nowArt.month, nowArt.day, 12);
      // Skip one day — yesterday is missing
      final twoDaysAgo = today.subtract(const Duration(days: 2));

      when(() => repo.listByUid('u1')).thenAnswer((_) async => [
            makeSession(
              id: 's1',
              startedAt: today,
              status: SessionStatus.finished,
              wasFullyCompleted: true,
            ),
            makeSession(
              id: 's2',
              startedAt: twoDaysAgo,
              status: SessionStatus.finished,
              wasFullyCompleted: true,
            ),
          ]);
      when(() => repo.listSetLogs(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
          )).thenAnswer((_) async => []);

      final container = makeContainer(repo: repo);
      addTearDown(container.dispose);

      final result = await container.read(weeklyInsightsProvider.future);
      expect(result!.streak, 1); // only today; gap breaks the chain
    });

    // SCENARIO-303: no finished sessions → streak is 0
    test('SCENARIO-303: no finished sessions → streak is 0', () async {
      final repo = MockSessionRepository();
      when(() => repo.listByUid('u1')).thenAnswer((_) async => []);

      final container = makeContainer(repo: repo);
      addTearDown(container.dispose);

      final result = await container.read(weeklyInsightsProvider.future);
      expect(result!.streak, 0);
    });

    // Extra: active sessions are excluded from streak
    test('active sessions not counted in streak', () async {
      final repo = MockSessionRepository();
      // UTC-flagged noon anchor on today's ART day (see SCENARIO-300).
      final nowArt = argentinaNow();
      final today = DateTime.utc(nowArt.year, nowArt.month, nowArt.day, 12);

      when(() => repo.listByUid('u1')).thenAnswer((_) async => [
            makeSession(
              id: 's1',
              startedAt: today,
              status: SessionStatus.active, // NOT finished — excluded
            ),
          ]);

      final container = makeContainer(repo: repo);
      addTearDown(container.dispose);

      final result = await container.read(weeklyInsightsProvider.future);
      expect(result!.streak, 0);
    });
  });

  group('weeklyInsightsProvider — monthSessionsCount (SCENARIO-304)', () {
    // SCENARIO-304: monthSessionsCount includes only current-month sessions
    test('SCENARIO-304: only current-month finished sessions counted',
        () async {
      final repo = MockSessionRepository();
      // monthSessionsCount uses the ART calendar month (#379). Anchor to
      // `argentinaNow()` and build UTC-flagged noon instants (= 09:00 ART, same
      // ART day/month under any runner), mirroring real UTC-flagged data.
      final nowArt = argentinaNow();
      final thisMonthDate = DateTime.utc(nowArt.year, nowArt.month, 1, 12);
      // Previous month, mid-month → unambiguously outside the current ART month.
      final prevMonthDate = DateTime.utc(
          nowArt.year, nowArt.month - 1 == 0 ? 12 : nowArt.month - 1, 15, 12);

      when(() => repo.listByUid('u1')).thenAnswer((_) async => [
            makeSession(
              id: 's-this',
              startedAt: thisMonthDate,
              status: SessionStatus.finished,
              wasFullyCompleted: true,
            ),
            makeSession(
              id: 's-prev',
              startedAt: prevMonthDate,
              status: SessionStatus.finished,
              wasFullyCompleted: true,
            ),
          ]);
      when(() => repo.listSetLogs(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
          )).thenAnswer((_) async => []);

      final container = makeContainer(repo: repo);
      addTearDown(container.dispose);

      final result = await container.read(weeklyInsightsProvider.future);
      // Only the session in the current month should count
      expect(result!.monthSessionsCount, greaterThanOrEqualTo(1));
      // The prev-month session must NOT be included
      // We check total: if both months same year, prevMonth sessions are excluded
      if (nowArt.month > 1) {
        expect(result.monthSessionsCount, 1);
      }
    });

    test('active sessions excluded from monthSessionsCount', () async {
      final repo = MockSessionRepository();
      // UTC-flagged noon anchor on today's ART day (see the streak group).
      final nowArt = argentinaNow();
      final today = DateTime.utc(nowArt.year, nowArt.month, nowArt.day, 12);

      when(() => repo.listByUid('u1')).thenAnswer((_) async => [
            makeSession(
              id: 's1',
              startedAt: today,
              status: SessionStatus.active,
            ),
          ]);

      final container = makeContainer(repo: repo);
      addTearDown(container.dispose);

      final result = await container.read(weeklyInsightsProvider.future);
      expect(result!.monthSessionsCount, 0);
    });

    test('multiple finished sessions this month counted correctly', () async {
      final repo = MockSessionRepository();
      // UTC-flagged noon anchors (days 1..5) within the current ART month.
      final nowArt = argentinaNow();

      when(() => repo.listByUid('u1')).thenAnswer((_) async => [
            for (var i = 0; i < 5; i++)
              makeSession(
                id: 's$i',
                startedAt: DateTime.utc(
                    nowArt.year, nowArt.month, (i + 1).clamp(1, 28), 12),
                status: SessionStatus.finished,
                wasFullyCompleted: true,
              ),
          ]);
      when(() => repo.listSetLogs(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
          )).thenAnswer((_) async => []);

      final container = makeContainer(repo: repo);
      addTearDown(container.dispose);

      final result = await container.read(weeklyInsightsProvider.future);
      expect(result!.monthSessionsCount, 5);
    });
  });
}
