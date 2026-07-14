import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/performance/application/performance_test_providers.dart';
import 'package:treino/features/performance/data/performance_test_repository.dart';
import 'package:treino/features/performance/domain/performance_test.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

/// [ownPerformanceTestsProvider] — la óptica del PROPIO atleta. Misma asimetría
/// que [ownMeasurementsProvider]; ver own_measurements_provider_test.dart.
void main() {
  const athleteId = 'athlete1';
  const otherAthlete = 'athlete2';
  const trainerA = 'trainerA';
  const trainerB = 'trainerB';

  Future<FakeFirebaseFirestore> seed() async {
    final firestore = FakeFirebaseFirestore();
    final repo = PerformanceTestRepository(firestore: firestore);

    await repo.add(PerformanceTest(
      id: '',
      athleteId: athleteId,
      recordedBy: trainerB, // un PF anterior
      recordedAt: DateTime.utc(2026, 3, 1),
      cmjCm: 34,
    ));
    await repo.add(PerformanceTest(
      id: '',
      athleteId: athleteId,
      recordedBy: trainerA, // el PF actual
      recordedAt: DateTime.utc(2026, 1, 1),
      cmjCm: 30,
    ));
    await repo.add(PerformanceTest(
      id: '',
      athleteId: otherAthlete,
      recordedBy: trainerA,
      recordedAt: DateTime.utc(2026, 2, 1),
      cmjCm: 45,
    ));

    return firestore;
  }

  test(
    'óptica del atleta: ve TODAS sus evaluaciones, sin importar qué entrenador '
    'las cargó — y ordenadas por fecha ascendente',
    () async {
      final firestore = await seed();

      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(firestore),
        currentUidProvider.overrideWithValue(athleteId),
      ]);
      addTearDown(container.dispose);

      final result =
          await container.read(ownPerformanceTestsProvider(athleteId).future);

      expect(result.map((t) => t.cmjCm), [30, 34]); // asc por recordedAt
      expect(
          result.map((t) => t.recordedBy), containsAll([trainerA, trainerB]));
      expect(result.any((t) => t.athleteId == otherAthlete), isFalse);
    },
  );

  test(
    'POR QUÉ existe este provider: el de óptica-entrenador, llamado por el '
    'propio atleta, devuelve VACÍO',
    () async {
      final firestore = await seed();

      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(firestore),
        currentUidProvider.overrideWithValue(athleteId),
      ]);
      addTearDown(container.dispose);

      final trainerVantage = await container
          .read(performanceTestsForAthleteProvider(athleteId).future);
      expect(trainerVantage, isEmpty);

      final ownVantage =
          await container.read(ownPerformanceTestsProvider(athleteId).future);
      expect(ownVantage, hasLength(2));
    },
  );

  test('uid vacío → lista vacía, sin tocar Firestore', () async {
    final container = ProviderContainer(overrides: [
      firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
      currentUidProvider.overrideWithValue(null),
    ]);
    addTearDown(container.dispose);

    expect(
        await container.read(ownPerformanceTestsProvider('').future), isEmpty);
  });
}
