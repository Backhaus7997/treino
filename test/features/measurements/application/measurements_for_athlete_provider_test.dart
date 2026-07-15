import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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

  // ── athlete-self-measurements: Q1 ∪ Q2 merge (T1, T2) ─────────────────────

  test(
    'T1: la vista del entrenador une lo que ÉL registró (Q1) con lo que el '
    'alumno se cargó a sí mismo (Q2), ordenado por fecha',
    () async {
      final firestore = FakeFirebaseFirestore();
      final repo = MeasurementRepository(firestore: firestore);

      // Q1 — trainer-recorded (recordedBy == coach).
      await repo.add(Measurement(
        id: '',
        athleteId: 'athleteX',
        recordedBy: 'coach',
        recordedAt: DateTime.utc(2026, 1, 1),
        weightKg: 80,
      ));
      // Q2 — athlete self-logged (recordedBy == athleteX).
      await repo.add(Measurement(
        id: '',
        athleteId: 'athleteX',
        recordedBy: 'athleteX',
        recordedAt: DateTime.utc(2026, 2, 1),
        weightKg: 78,
      ));

      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(firestore),
        currentUidProvider.overrideWithValue('coach'),
      ]);
      addTearDown(container.dispose);

      // Espera a que el merge tenga AMBOS orígenes (Q1 puede emitir antes que Q2).
      final result = await container
          .read(measurementsForAthleteProvider('athleteX').stream)
          .firstWhere((list) => list.length == 2);

      expect(
          result.map((m) => m.recordedBy), ['coach', 'athleteX']); // asc fecha
      expect(result.map((m) => m.weightKg), [80, 78]);
    },
  );

  test(
    'T2: Q2 emite datos y LUEGO es revocada (error) → el error NO se surfacea '
    'y las filas self-logged se quitan; el PF sigue viendo lo suyo (Q1)',
    () async {
      // fake_cloud_firestore no aplica reglas → no puede emitir permission-
      // denied. Se controlan los dos streams a mano para ejercitar de verdad el
      // camino de error de Q2 (lo que `.future` NO probaba: tomaba sólo el
      // primer evento, que siempre es Q1).
      final q1 = StreamController<List<Measurement>>();
      final q2 = StreamController<List<Measurement>>();
      addTearDown(q1.close);
      addTearDown(q2.close);

      final repo = _MockMeasurementRepository();
      when(() => repo.watchForTrainerAthlete('coach', 'athleteX'))
          .thenAnswer((_) => q1.stream);
      when(() => repo.watchSelfLoggedForAthlete('athleteX'))
          .thenAnswer((_) => q2.stream);

      final container = ProviderContainer(overrides: [
        measurementRepositoryProvider.overrideWithValue(repo),
        currentUidProvider.overrideWithValue('coach'),
      ]);
      addTearDown(container.dispose);

      final states = <AsyncValue<List<Measurement>>>[];
      container.listen(
        measurementsForAthleteProvider('athleteX'),
        (_, next) => states.add(next),
        fireImmediately: true,
      );

      Future<void> tick() => Future<void>.delayed(Duration.zero);

      final coachDoc = Measurement(
        id: 'c1',
        athleteId: 'athleteX',
        recordedBy: 'coach',
        recordedAt: DateTime.utc(2026, 1, 1),
        weightKg: 80,
      );
      final selfDoc = Measurement(
        id: 's1',
        athleteId: 'athleteX',
        recordedBy: 'athleteX',
        recordedAt: DateTime.utc(2026, 2, 1),
        weightKg: 78,
      );

      q1.add([coachDoc]);
      await tick();
      q2.add([selfDoc]); // Q2 aporta lo self-logged...
      await tick();
      q2.addError(Exception('permission-denied')); // ...y luego se revoca.
      await tick();

      // El error de Q2 nunca vuelve el provider a estado de error.
      expect(states.any((s) => s.hasError), isFalse);
      // Tras la revocación, la última lista es SÓLO lo del PF (self reseteado).
      final last = container.read(measurementsForAthleteProvider('athleteX'));
      expect(last.value!.map((m) => m.recordedBy), ['coach']);
    },
  );

  // Ancla adicional: un error de Q1 (el PF leyendo lo SUYO) SÍ debe surfacearse
  // — es un fallo real, no se enmascara con lo self-logged (review F1).
  test('un error de Q1 se propaga (no lo tapa Q2)', () async {
    final q1 = StreamController<List<Measurement>>();
    final q2 = StreamController<List<Measurement>>();
    addTearDown(q1.close);
    addTearDown(q2.close);

    final repo = _MockMeasurementRepository();
    when(() => repo.watchForTrainerAthlete('coach', 'athleteX'))
        .thenAnswer((_) => q1.stream);
    when(() => repo.watchSelfLoggedForAthlete('athleteX'))
        .thenAnswer((_) => q2.stream);

    final container = ProviderContainer(overrides: [
      measurementRepositoryProvider.overrideWithValue(repo),
      currentUidProvider.overrideWithValue('coach'),
    ]);
    addTearDown(container.dispose);

    container.listen(
      measurementsForAthleteProvider('athleteX'),
      (_, __) {},
      fireImmediately: true,
    );

    Future<void> tick() => Future<void>.delayed(Duration.zero);

    q2.add([
      Measurement(
        id: 's1',
        athleteId: 'athleteX',
        recordedBy: 'athleteX',
        recordedAt: DateTime.utc(2026, 2, 1),
      ),
    ]);
    await tick();
    q1.addError(Exception('unavailable')); // Q1 falla ANTES de emitir datos.
    await tick();

    // El error del PF se ve, no lo tapa lo self-logged de Q2.
    expect(
      container.read(measurementsForAthleteProvider('athleteX')).hasError,
      isTrue,
    );
  });
}

class _MockMeasurementRepository extends Mock
    implements MeasurementRepository {}
