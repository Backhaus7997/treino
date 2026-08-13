import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/measurements/application/measurement_providers.dart';
import 'package:treino/features/measurements/data/measurement_repository.dart';
import 'package:treino/features/measurements/domain/measurement.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

/// [ownMeasurementsProvider] — la óptica del PROPIO atleta.
///
/// Contraparte de [measurementsForAthleteProvider] (óptica del ENTRENADOR, que
/// filtra por `recordedBy == trainerUid`). La distinción NO es cosmética: el
/// atleta tiene que ver todo lo suyo, lo haya cargado el PF que lo entrena hoy
/// o uno anterior.
void main() {
  const athleteId = 'athlete1';
  const otherAthlete = 'athlete2';
  const trainerA = 'trainerA';
  const trainerB = 'trainerB';

  /// Siembra: 2 mediciones del alumno cargadas por DOS entrenadores distintos,
  /// + 1 de otro alumno (que nunca debe filtrarse).
  Future<FakeFirebaseFirestore> seed() async {
    final firestore = FakeFirebaseFirestore();
    final repo = MeasurementRepository(firestore: firestore);

    await repo.add(Measurement(
      id: '',
      athleteId: athleteId,
      recordedBy: trainerB, // un PF anterior
      recordedAt: DateTime.utc(2026, 3, 1),
      weightKg: 78,
    ));
    await repo.add(Measurement(
      id: '',
      athleteId: athleteId,
      recordedBy: trainerA, // el PF actual
      recordedAt: DateTime.utc(2026, 1, 1),
      weightKg: 80,
    ));
    await repo.add(Measurement(
      id: '',
      athleteId: otherAthlete,
      recordedBy: trainerA,
      recordedAt: DateTime.utc(2026, 2, 1),
      weightKg: 70,
    ));

    return firestore;
  }

  test(
    'óptica del atleta: ve TODAS sus mediciones, sin importar qué entrenador '
    'las cargó — y ordenadas por fecha ascendente',
    () async {
      final firestore = await seed();

      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(firestore),
        // El atleta autenticado mirando lo suyo.
        currentUidProvider.overrideWithValue(athleteId),
      ]);
      addTearDown(container.dispose);

      final result =
          await container.read(ownMeasurementsProvider(athleteId).future);

      // Las 2 propias (de AMBOS entrenadores), nunca la del otro alumno.
      expect(result.map((m) => m.weightKg), [80, 78]); // asc por recordedAt
      expect(
          result.map((m) => m.recordedBy), containsAll([trainerA, trainerB]));
      expect(result.any((m) => m.athleteId == otherAthlete), isFalse);
    },
  );

  test(
    'POR QUÉ existe este provider: el de óptica-entrenador, llamado por el '
    'propio atleta, devuelve VACÍO',
    () async {
      // Éste es el bug que el provider nuevo evita. measurementsForAthlete
      // arma la query `recordedBy == currentUid`. Si el caller es el atleta,
      // eso resuelve a `recordedBy == athleteId` — y el atleta NUNCA registró
      // nada (hoy sólo un rol `trainer` puede crear mediciones). Reusar aquel
      // provider en la pantalla del alumno habría dado una pantalla vacía,
      // silenciosamente, para todos.
      final firestore = await seed();

      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(firestore),
        currentUidProvider.overrideWithValue(athleteId),
      ]);
      addTearDown(container.dispose);

      final trainerVantage = await container
          .read(measurementsForAthleteProvider(athleteId).future);
      expect(trainerVantage, isEmpty);

      // El provider correcto, mismo container, mismo atleta → 2 resultados.
      final ownVantage =
          await container.read(ownMeasurementsProvider(athleteId).future);
      expect(ownVantage, hasLength(2));
    },
  );

  test('uid vacío → lista vacía, sin tocar Firestore', () async {
    final container = ProviderContainer(overrides: [
      firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
      currentUidProvider.overrideWithValue(null),
    ]);
    addTearDown(container.dispose);

    expect(await container.read(ownMeasurementsProvider('').future), isEmpty);
  });
}
