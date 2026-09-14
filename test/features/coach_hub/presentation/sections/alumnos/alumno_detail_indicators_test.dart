import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/coach/application/athlete_file_providers.dart';
import 'package:treino/features/coach/application/athlete_note_providers.dart';
import 'package:treino/features/coach/application/follow_up_entry_providers.dart';
import 'package:treino/features/coach/application/nutrition_plan_providers.dart';
import 'package:treino/features/coach/domain/athlete_file.dart';
import 'package:treino/features/coach/domain/athlete_note.dart';
import 'package:treino/features/coach/domain/follow_up_entry.dart';
import 'package:treino/features/coach/domain/nutrition_plan.dart';
import 'package:treino/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart';
import 'package:treino/features/measurements/application/measurement_providers.dart';
import 'package:treino/features/measurements/domain/measurement.dart';
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart';
import 'package:treino/features/payments/domain/athlete_billing.dart';
import 'package:treino/features/performance/application/performance_test_providers.dart';
import 'package:treino/features/performance/domain/performance_test.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/session.dart';

const _athleteId = 'a1';
const _trainerId = 't1';
const _trainerAthlete = (trainerId: _trainerId, athleteId: _athleteId);

void main() {
  test('data conocida compone un flag por grupo', () async {
    final container = ProviderContainer(
      overrides: [
        currentUidProvider.overrideWithValue(_trainerId),
        sessionsByUidProvider.overrideWith((ref, id) => const <Session>[]),
        assignedRoutinesByTrainerProvider.overrideWith(
          (ref, key) => [
            const Routine(
              id: 'r1',
              name: 'Fuerza',
              level: ExperienceLevel.intermediate,
              days: [],
            ),
          ],
        ),
        measurementsForAthleteProvider.overrideWith(
          (ref, id) => Stream.value([
            Measurement(
              id: 'm1',
              athleteId: _athleteId,
              recordedBy: _trainerId,
              recordedAt: DateTime.utc(2026, 1, 1),
              weightKg: 70,
            ),
          ]),
        ),
        performanceTestsForAthleteProvider.overrideWith(
          (ref, id) => Stream.value(const <PerformanceTest>[]),
        ),
        nutritionPlanProvider.overrideWith(
          (ref, key) => Stream.value(
            NutritionPlan(
              id: 'np1',
              trainerId: _trainerId,
              athleteId: _athleteId,
              title: 'Plan',
              meals: const [],
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          ),
        ),
        athleteFilesProvider.overrideWith(
          (ref, key) => Stream.value(const <AthleteFile>[]),
        ),
        athleteNoteProvider.overrideWith(
          (ref, key) => Stream.value(
            AthleteNote(
              trainerId: _trainerId,
              athleteId: _athleteId,
              note: 'Priorizar técnica',
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          ),
        ),
        followUpEntriesProvider.overrideWith(
          (ref, key) => Stream.value(const <FollowUpEntry>[]),
        ),
        hasUnreadFromProvider(_athleteId).overrideWithValue(true),
        pagosPorCobrarProvider.overrideWithValue(
          const AsyncData([
            CobroPendiente(
              athleteId: _athleteId,
              amountArs: 10000,
              cadence: BillingCadence.suelto,
              concept: 'Sesión',
            ),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      alumnoDetailIndicatorsProvider(_athleteId),
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await Future.wait<Object?>([
      container.read(sessionsByUidProvider(_athleteId).future),
      container.read(assignedRoutinesByTrainerProvider(_trainerAthlete).future),
      container.read(measurementsForAthleteProvider(_athleteId).future),
      container.read(performanceTestsForAthleteProvider(_athleteId).future),
      container.read(nutritionPlanProvider(_trainerAthlete).future),
      container.read(athleteFilesProvider(_trainerAthlete).future),
      container.read(athleteNoteProvider(_trainerAthlete).future),
      container.read(followUpEntriesProvider(_trainerAthlete).future),
    ]);
    expect(
      container.read(alumnoDetailIndicatorsProvider(_athleteId)),
      const AlumnoDetailIndicators(
        entrenamiento: AlumnoGrupoEstado.conContenido,
        progreso: AlumnoGrupoEstado.conContenido,
        plan: AlumnoGrupoEstado.conContenido,
        chat: AlumnoGrupoEstado.requiereAtencion,
        privado: AlumnoGrupoEstado.conContenido,
        pagos: AlumnoGrupoEstado.requiereAtencion,
      ),
    );
  });

  test('loading no se interpreta como contenido', () {
    final container = ProviderContainer(overrides: _unknownOverrides());
    addTearDown(container.dispose);
    final subscription = container.listen(
      alumnoDetailIndicatorsProvider(_athleteId),
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    expect(container.read(sessionsByUidProvider(_athleteId)).isLoading, isTrue);
    expect(
      container.read(alumnoDetailIndicatorsProvider(_athleteId)),
      const AlumnoDetailIndicators(),
    );
  });

  test('error no se interpreta como contenido', () async {
    final container = ProviderContainer(overrides: _unknownOverrides(true));
    addTearDown(container.dispose);
    final subscription = container.listen(
      alumnoDetailIndicatorsProvider(_athleteId),
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await Future<void>.delayed(Duration.zero);
    expect(container.read(measurementsForAthleteProvider(_athleteId)).hasError,
        isTrue);
    expect(
      container.read(alumnoDetailIndicatorsProvider(_athleteId)),
      const AlumnoDetailIndicators(),
    );
  });
}

List<Override> _unknownOverrides([bool error = false]) => [
      currentUidProvider.overrideWithValue(_trainerId),
      sessionsByUidProvider.overrideWith(
        (ref, id) => error
            ? Future<List<Session>>.error(StateError('boom'))
            : Completer<List<Session>>().future,
      ),
      assignedRoutinesByTrainerProvider.overrideWith(
        (ref, key) => error
            ? Future<List<Routine>>.error(StateError('boom'))
            : Completer<List<Routine>>().future,
      ),
      measurementsForAthleteProvider.overrideWith(
        (ref, id) => error
            ? Stream<List<Measurement>>.error(StateError('boom'))
            : const Stream.empty(),
      ),
      performanceTestsForAthleteProvider.overrideWith(
        (ref, id) => error
            ? Stream<List<PerformanceTest>>.error(StateError('boom'))
            : const Stream.empty(),
      ),
      nutritionPlanProvider.overrideWith(
        (ref, key) => error
            ? Stream<NutritionPlan?>.error(StateError('boom'))
            : const Stream.empty(),
      ),
      athleteFilesProvider.overrideWith(
        (ref, key) => error
            ? Stream<List<AthleteFile>>.error(StateError('boom'))
            : const Stream.empty(),
      ),
      athleteNoteProvider.overrideWith(
        (ref, key) => error
            ? Stream<AthleteNote?>.error(StateError('boom'))
            : const Stream.empty(),
      ),
      followUpEntriesProvider.overrideWith(
        (ref, key) => error
            ? Stream<List<FollowUpEntry>>.error(StateError('boom'))
            : const Stream.empty(),
      ),
      hasUnreadFromProvider(_athleteId).overrideWithValue(false),
      pagosPorCobrarProvider.overrideWithValue(
        error
            ? AsyncError<List<CobroPendiente>>(
                StateError('boom'),
                StackTrace.empty,
              )
            : const AsyncLoading(),
      ),
    ];
