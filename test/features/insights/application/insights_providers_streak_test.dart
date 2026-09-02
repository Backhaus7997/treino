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

  // SCENARIO-300..303 se releyeron cuando la racha pasó de días a SEMANAS.
  // El comportamiento fino (qué cuenta una semana, por qué la semana en curso
  // no corta) está cubierto en `test/core/utils/weekly_streak_calculator_test`;
  // acá se prueba el CABLEADO: que el provider alimente el cálculo con la
  // lista completa de sesiones y que sólo cuenten las que califican.
  //
  // Todos los fixtures se anclan al LUNES de la semana en curso, no a "hoy".
  // Un fixture de hoy/ayer daría un resultado distinto según el día en que
  // corra la suite: si hoy es lunes, "ayer" cae en la semana anterior.
  //
  // El container no tiene rutina activa, así que el objetivo cae al fallback
  // de 1 sesión por semana. Es lo correcto para estos tests: miden bucketeo,
  // no umbral.
  group('weeklyInsightsProvider — racha semanal (SCENARIO-300..303)', () {
    /// Mediodía UTC (= 09:00 ART) del lunes de hace [weeksAgo] semanas.
    DateTime weekAt(int weeksAgo) {
      final monday = mondayOfWeekArt(argentinaNow());
      return DateTime.utc(
        monday.year,
        monday.month,
        monday.day - (7 * weeksAgo),
        12,
      );
    }

    void stubNoSetLogs(MockSessionRepository repo) {
      when(() => repo.listSetLogs(
            uid: any(named: 'uid'),
            sessionId: any(named: 'sessionId'),
          )).thenAnswer((_) async => []);
    }

    // SCENARIO-300: la semana en curso ya cumplida entra en la racha.
    test('SCENARIO-300: semanas consecutivas cumplidas → racha completa',
        () async {
      final repo = MockSessionRepository();
      when(() => repo.listByUid('u1')).thenAnswer((_) async => [
            makeSession(
              id: 's0',
              startedAt: weekAt(0),
              status: SessionStatus.finished,
              wasFullyCompleted: true,
            ),
            makeSession(
              id: 's1',
              startedAt: weekAt(1),
              status: SessionStatus.finished,
              wasFullyCompleted: true,
            ),
          ]);
      stubNoSetLogs(repo);

      final container = makeContainer(repo: repo);
      addTearDown(container.dispose);

      final result = await container.read(weeklyInsightsProvider.future);
      expect(result!.streak, 2);
    });

    // SCENARIO-301: la semana en curso vacía NO corta — es la contraparte
    // del día de gracia que tenía la racha por día.
    test('SCENARIO-301: semana en curso sin entrenar → no corta la racha',
        () async {
      final repo = MockSessionRepository();
      when(() => repo.listByUid('u1')).thenAnswer((_) async => [
            makeSession(
              id: 's1',
              startedAt: weekAt(1),
              status: SessionStatus.finished,
              wasFullyCompleted: true,
            ),
            makeSession(
              id: 's2',
              startedAt: weekAt(2),
              status: SessionStatus.finished,
              wasFullyCompleted: true,
            ),
          ]);
      stubNoSetLogs(repo);

      final container = makeContainer(repo: repo);
      addTearDown(container.dispose);

      final result = await container.read(weeklyInsightsProvider.future);
      expect(result!.streak, 2);
    });

    // SCENARIO-302: una semana CERRADA sin sesiones sí corta.
    test('SCENARIO-302: hueco de una semana cerrada → racha más corta',
        () async {
      final repo = MockSessionRepository();
      when(() => repo.listByUid('u1')).thenAnswer((_) async => [
            makeSession(
              id: 's0',
              startedAt: weekAt(0),
              status: SessionStatus.finished,
              wasFullyCompleted: true,
            ),
            // weekAt(1) vacía → corta acá. La de hace 2 semanas no se cuenta.
            makeSession(
              id: 's2',
              startedAt: weekAt(2),
              status: SessionStatus.finished,
              wasFullyCompleted: true,
            ),
          ]);
      stubNoSetLogs(repo);

      final container = makeContainer(repo: repo);
      addTearDown(container.dispose);

      final result = await container.read(weeklyInsightsProvider.future);
      expect(result!.streak, 1);
    });

    // SCENARIO-303: sin sesiones terminadas → 0.
    test('SCENARIO-303: sin sesiones terminadas → racha 0', () async {
      final repo = MockSessionRepository();
      when(() => repo.listByUid('u1')).thenAnswer((_) async => []);

      final container = makeContainer(repo: repo);
      addTearDown(container.dispose);

      final result = await container.read(weeklyInsightsProvider.future);
      expect(result!.streak, 0);
    });

    // Extra: una sesión en curso no cuenta para la racha.
    test('las sesiones activas no cuentan para la racha', () async {
      final repo = MockSessionRepository();
      when(() => repo.listByUid('u1')).thenAnswer((_) async => [
            makeSession(
              id: 's1',
              startedAt: weekAt(0),
              status: SessionStatus.active, // NO finished — excluida
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
