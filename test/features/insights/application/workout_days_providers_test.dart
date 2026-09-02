import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/core/utils/argentina_time.dart';
import 'package:treino/features/insights/application/workout_days_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/session_status.dart';

import '../../workout/application/stub_factories.dart';

class MockSessionRepository extends Mock implements SessionRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(makeSession());
  });

  group('athleteWorkoutDaysProvider', () {
    test('empty uid → empty trained days, zero streak, no repo call', () async {
      final repo = MockSessionRepository();

      final container = ProviderContainer(overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(
        athleteWorkoutDaysProvider(
          (uid: '', month: DateTime(2026, 6)),
        ).future,
      );

      expect(result.trainedDays, isEmpty);
      expect(result.streak, 0);
      verifyNever(() => repo.listByUid(any()));
    });

    test('marks exactly the trained days of the selected month', () async {
      final repo = MockSessionRepository();
      when(() => repo.listByUid('u1')).thenAnswer((_) async => [
            // [#379] Real UTC instants at NOON → unambiguous Argentina days
            // (Jun 1 / Jun 30); day-boundary LOCAL midnights would shift −3h
            // into the previous day/month under toArgentina.
            makeSession(
              id: 's1',
              startedAt: DateTime.utc(2026, 6, 1, 12),
              status: SessionStatus.finished,
              wasFullyCompleted: true,
            ),
            makeSession(
              id: 's2',
              startedAt: DateTime.utc(2026, 6, 30, 12),
              status: SessionStatus.finished,
              wasFullyCompleted: true,
            ),
            // Outside the selected month → excluded.
            makeSession(
              id: 's3',
              startedAt: DateTime(2026, 5, 15),
              status: SessionStatus.finished,
              wasFullyCompleted: true,
            ),
          ]);

      final container = ProviderContainer(overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(
        athleteWorkoutDaysProvider(
          (uid: 'u1', month: DateTime(2026, 6)),
        ).future,
      );

      expect(result.trainedDays, {
        DateTime(2026, 6, 1),
        DateTime(2026, 6, 30),
      });
    });

    test('la racha cuenta SEMANAS sobre la lista completa de sesiones',
        () async {
      final repo = MockSessionRepository();
      // Anclado al LUNES de la semana en curso, no a "hoy". Con la racha por
      // día un fixture de hoy+ayer daba 2 siempre; con la racha por semana
      // daría 1 o 2 según el día en que corra la suite (si hoy es lunes,
      // "ayer" cae en la semana anterior). Tres semanas consecutivas con una
      // sesión cada una dan 3 corra el día que corra.
      //
      // Sin rutina activa en el container, el objetivo cae al fallback de 1
      // sesión por semana — que es justamente lo que este test quiere medir:
      // el bucketeo semanal, no el umbral.
      final monday = mondayOfWeekArt(argentinaNow());
      DateTime weekAt(int weeksAgo) => DateTime.utc(
            monday.year,
            monday.month,
            monday.day - (7 * weeksAgo),
            12, // mediodía UTC = 09:00 ART, mismo día bajo cualquier runner
          );

      when(() => repo.listByUid('u1')).thenAnswer((_) async => [
            makeSession(
                id: 's0',
                startedAt: weekAt(0),
                status: SessionStatus.finished,
                wasFullyCompleted: true),
            makeSession(
                id: 's1',
                startedAt: weekAt(1),
                status: SessionStatus.finished,
                wasFullyCompleted: true),
            makeSession(
                id: 's2',
                startedAt: weekAt(2),
                status: SessionStatus.finished,
                wasFullyCompleted: true),
          ]);

      final container = ProviderContainer(overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);

      final nowArt = argentinaNow();
      final result = await container.read(
        athleteWorkoutDaysProvider(
          (uid: 'u1', month: DateTime(nowArt.year, nowArt.month)),
        ).future,
      );

      expect(result.streak, 3);
    });
  });
}
