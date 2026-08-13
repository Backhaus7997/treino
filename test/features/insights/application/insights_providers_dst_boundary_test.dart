import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/insights/application/insights_providers.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/exercise.dart';

import '../../workout/application/stub_factories.dart';

class MockSessionRepository extends Mock implements SessionRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(makeSession());
    registerFallbackValue(makeSetLog());
  });

  // Regresión DST: las fronteras de semana se computan con aritmética de
  // calendario (DateTime(y, m, d + N)), no con Duration(days: N). El
  // constructor normaliza a medianoche local aun cruzando un cambio de
  // horario; sumar un Duration de días aterriza en 23:00 o 01:00. Este test
  // verifica la INVARIANTE portable que garantiza el fix —weekStart en
  // medianoche local del lunes y weekEnd justo antes del lunes siguiente—
  // sin depender de la zona horaria del runner.
  test('SCENARIO-407: week boundaries land on local midnight (no DST drift)',
      () async {
    final repo = MockSessionRepository();
    when(() => repo.listByUid('u1')).thenAnswer((_) async => const []);

    final container = ProviderContainer(overrides: [
      currentUidProvider.overrideWithValue('u1'),
      sessionRepositoryProvider.overrideWithValue(repo),
      exercisesProvider.overrideWith((ref) async => const <Exercise>[]),
    ]);
    addTearDown(container.dispose);

    final result = await container.read(weeklyInsightsProvider.future);
    expect(result, isNotNull);

    final weekStart = result!.weekStart;
    // weekStart es lunes a medianoche local exacta.
    expect(weekStart.weekday, DateTime.monday);
    expect(weekStart.hour, 0);
    expect(weekStart.minute, 0);
    expect(weekStart.second, 0);
    expect(weekStart.millisecond, 0);

    // weekEnd es el último instante de la semana: 1ms antes del siguiente
    // lunes a medianoche, calculado por calendario (no por Duration). [#379]
    // Los bordes viven en el frame ART (UTC-flagged), así que el ancla de
    // comparación también debe ser DateTime.utc para que coincida el flag.
    final nextMonday = DateTime.utc(
      weekStart.year,
      weekStart.month,
      weekStart.day + 7,
    );
    expect(
      result.weekEnd,
      nextMonday.subtract(const Duration(milliseconds: 1)),
    );
    // El día calendario de weekEnd es domingo (último día de la semana).
    expect(result.weekEnd.weekday, DateTime.sunday);
  });
}
