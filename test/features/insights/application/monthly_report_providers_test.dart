import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/insights/application/monthly_report_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/session_status.dart';

import '../../workout/application/stub_factories.dart';

class MockSessionRepository extends Mock implements SessionRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(makeSession());
    registerFallbackValue(makeSetLog());
  });

  group('athleteMonthlyReportProvider', () {
    test('returns 12 empty-month points when uid has no sessions', () async {
      final repo = MockSessionRepository();
      when(() => repo.listByUid('u1')).thenAnswer((_) async => const []);

      final container = ProviderContainer(overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);

      final report =
          await container.read(athleteMonthlyReportProvider('u1').future);
      expect(report.points.length, 12);
      expect(report.points.every((p) => p.workoutsCount == 0), isTrue);
    });

    test('returns empty report immediately for empty uid, no repo call',
        () async {
      final repo = MockSessionRepository();

      final container = ProviderContainer(overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);

      final report =
          await container.read(athleteMonthlyReportProvider('').future);
      expect(report.points.length, 12);
      verifyNever(() => repo.listByUid(any()));
    });

    test('reads the FULL session list (not a capped scan) and sums setLogs',
        () async {
      final repo = MockSessionRepository();
      final now = DateTime.now();
      final session = makeSession(
        id: 's1',
        startedAt: now,
        status: SessionStatus.finished,
        durationMin: 45,
        totalVolumeKg: 2000,
      );
      when(() => repo.listByUid('u1')).thenAnswer((_) async => [session]);
      when(() => repo.listSetLogs(uid: 'u1', sessionId: 's1'))
          .thenAnswer((_) async => [makeSetLog(), makeSetLog(id: 'sl2')]);

      final container = ProviderContainer(overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);

      final report =
          await container.read(athleteMonthlyReportProvider('u1').future);
      final currentMonthPoint = report.points.last;
      expect(currentMonthPoint.workoutsCount, 1);
      expect(currentMonthPoint.durationMin, 45);
      expect(currentMonthPoint.volumeKg, 2000);
      expect(currentMonthPoint.setsCount, 2);
    });
  });
}
