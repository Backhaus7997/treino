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

void main() {
  // ---------------------------------------------------------------------------
  // measurementsForAthleteProvider corre en contexto de ENTRENADOR. Las reglas
  // de Firestore solo le permiten leer mediciones donde `recordedBy == uid`, por
  // lo que la query es `recordedBy + athleteId`. Un `where athleteId ==` a secas
  // es DENEGADO para el entrenador (eso rompía el Resumen/Progreso del Coach
  // Hub). Por eso el provider devuelve SOLO lo que el entrenador actual registró
  // para ese alumno. (FakeFirebaseFirestore no aplica reglas, pero validamos el
  // contrato del query: filtra por recordedBy Y athleteId.)
  // ---------------------------------------------------------------------------
  test(
    'vista entrenador: devuelve solo lo que registró el entrenador actual '
    'para ese alumno',
    () async {
      final firestore = FakeFirebaseFirestore();
      final repo = MeasurementRepository(firestore: firestore);

      const athleteId = 'athlete1';
      const otherAthlete = 'athlete2';
      const currentTrainer = 'trainerT2';
      const otherTrainer = 'trainerT1';

      // (a) Otro entrenador, mismo alumno → NO visible (filtro recordedBy).
      await repo.add(Measurement(
        id: '',
        athleteId: athleteId,
        recordedBy: otherTrainer,
        recordedAt: DateTime.utc(2026, 1, 1),
        weightKg: 80,
      ));
      // (b) Entrenador actual, mismo alumno → visible.
      await repo.add(Measurement(
        id: '',
        athleteId: athleteId,
        recordedBy: currentTrainer,
        recordedAt: DateTime.utc(2026, 2, 1),
        weightKg: 79,
      ));
      // (c) Entrenador actual, OTRO alumno → NO visible (filtro athleteId).
      await repo.add(Measurement(
        id: '',
        athleteId: otherAthlete,
        recordedBy: currentTrainer,
        recordedAt: DateTime.utc(2026, 3, 1),
        weightKg: 70,
      ));

      final container = ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          currentUidProvider.overrideWithValue(currentTrainer),
        ],
      );
      addTearDown(container.dispose);

      final result = await container
          .read(measurementsForAthleteProvider(athleteId).future);

      expect(result.map((m) => m.weightKg), [79]);
      expect(result.single.recordedBy, currentTrainer);
      expect(result.single.athleteId, athleteId);
    },
  );

  test('devuelve vacío cuando no hay entrenador autenticado', () async {
    final firestore = FakeFirebaseFirestore();
    final container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        currentUidProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);

    final result =
        await container.read(measurementsForAthleteProvider('athlete1').future);

    expect(result, isEmpty);
  });
}
