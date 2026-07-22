import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/core/utils/argentina_time.dart';
import 'package:treino/features/insights/application/insights_providers.dart';
import 'package:treino/features/insights/application/muscle_distribution_providers.dart';
import 'package:treino/features/insights/domain/chart_period.dart';
import 'package:treino/features/insights/domain/muscle_group.dart';
import 'package:treino/features/insights/domain/radar_axis.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/session_status.dart';

import '../../workout/application/stub_factories.dart';

class MockSessionRepository extends Mock implements SessionRepository {}

// [#442] Paridad del agregado semanal: la card SEMANA del hub, la pantalla de
// semana y volume-by-group leen athleteWeekInsightsProvider; el radar lee
// muscleDistributionInsightsProvider. Ambos deben contar LOS MISMOS sets para
// la misma semana — antes del fix, el weekly resolvía los ejercicios custom
// SOLO vía la rutina de la sesión más reciente de todo el historial y
// descartaba en silencio los sets custom de cualquier otra rutina de la
// semana (cambio de plan a mitad de semana, o paging a semanas pasadas).

Exercise _ex({required String id, required String muscleGroup}) => Exercise(
      id: id,
      name: id,
      muscleGroup: muscleGroup,
      category: 'compound',
    );

/// Instante real (UTC) cuyo reloj de pared en Argentina es [artWallClock]
/// (frame ART UTC-flagged) — mismo patrón que insights_gap_test.
DateTime _startedAtForArt(DateTime artWallClock) =>
    artWallClock.add(argentinaUtcOffset);

void main() {
  setUpAll(() {
    registerFallbackValue(makeSession());
    registerFallbackValue(makeSetLog());
  });

  // Lunes 13 jul 2026 — ancla ABSOLUTA para los tests deterministas de
  // athleteWeekInsightsProvider (la family key acepta cualquier weekStart, no
  // hace falta que sea la semana del reloj real).
  final pinnedMonday = DateTime.utc(2026, 7, 13);

  test(
      '#442 parity: hub, pantalla de semana y radar cuentan los MISMOS sets '
      'para una semana que abarca dos rutinas', () async {
    final repo = MockSessionRepository();

    // Semana ACTUAL (el radar ancla su ventana thisWeek en argentinaNow(), no
    // inyectable) — fixtures relativos al lunes ART, TZ-independientes.
    final artMonday = mondayOfWeek(argentinaNow());
    final sNew = makeSession(
      id: 's-new',
      startedAt:
          _startedAtForArt(artMonday.add(const Duration(days: 2, hours: 10))),
      status: SessionStatus.finished,
      wasFullyCompleted: true,
      routineId: 'rNew',
    );
    final sOld = makeSession(
      id: 's-old',
      startedAt: _startedAtForArt(artMonday.add(const Duration(hours: 10))),
      status: SessionStatus.finished,
      wasFullyCompleted: true,
      routineId: 'rOld',
    );
    // DESC por startedAt (contrato listByUid): la más nueva primero.
    final sessions = [sNew, sOld];
    when(() => repo.listByUid('u1')).thenAnswer((_) async => sessions);

    // sNew: 2 sets de un custom del plan nuevo + 1 set de catálogo.
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-new'))
        .thenAnswer((_) async => [
              makeSetLog(id: 'n1', exerciseId: 'c-new', setNumber: 1),
              makeSetLog(id: 'n2', exerciseId: 'c-new', setNumber: 2),
              makeSetLog(id: 'n3', exerciseId: 'e-back', setNumber: 1),
            ]);
    // sOld: 3 sets de un custom que SOLO la rutina vieja conoce.
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-old'))
        .thenAnswer((_) async => [
              makeSetLog(id: 'o1', exerciseId: 'c-old', setNumber: 1),
              makeSetLog(id: 'o2', exerciseId: 'c-old', setNumber: 2),
              makeSetLog(id: 'o3', exerciseId: 'c-old', setNumber: 3),
            ]);

    final rNew = makeRoutine(id: 'rNew', days: [
      makeDay(slots: [
        makeSlot(exerciseId: 'c-new', muscleGroup: 'chest', targetSets: 3),
      ]),
    ]);
    final rOld = makeRoutine(id: 'rOld', days: [
      makeDay(slots: [
        makeSlot(exerciseId: 'c-old', muscleGroup: 'back', targetSets: 3),
      ]),
    ]);

    final container = ProviderContainer(overrides: [
      currentUidProvider.overrideWithValue('u1'),
      sessionRepositoryProvider.overrideWithValue(repo),
      // El radar lee la lista vía sessionsByUidProvider; el weekly vía
      // repo.listByUid directo. MISMA lista para ambos caminos.
      sessionsByUidProvider('u1').overrideWith((ref) async => sessions),
      exercisesProvider.overrideWith(
          (ref) async => [_ex(id: 'e-back', muscleGroup: 'back')]),
      routineByIdProvider('rNew').overrideWith((ref) async => rNew),
      visibleRoutineByIdProvider('rNew').overrideWith((ref) async => rNew),
      visibleRoutineByIdProvider('rOld').overrideWith((ref) async => rOld),
    ]);
    addTearDown(container.dispose);

    // Pantalla de semana (family paginable) y hub (wrapper de semana actual).
    final week = await container.read(
      athleteWeekInsightsProvider((uid: 'u1', weekStart: artMonday)).future,
    );
    final hub = await container.read(weeklyInsightsProvider.future);
    // Radar de distribución muscular, período "esta semana" (misma ventana
    // [lunes, lunes+7) en frame ART).
    final radar = await container.read(
      muscleDistributionInsightsProvider(
          (uid: 'u1', period: ChartPeriod.thisWeek)).future,
    );

    // Los custom de AMBAS rutinas cuentan: 2 chest + (3+1) back.
    expect(week!.setsByGroup[MuscleGroupDisplay.pecho], 2);
    expect(week.setsByGroup[MuscleGroupDisplay.espalda], 4);

    // Hub y pantalla derivan del MISMO agregador → idénticos.
    expect(hub!.setsByGroup, equals(week.setsByGroup));

    // Paridad con el radar: mismo total y mismos buckets tras el fold
    // MuscleGroupDisplay → RadarAxis.
    final weekByAxis = <RadarAxis, int>{};
    week.setsByGroup.forEach((group, sets) {
      final axis = RadarAxis.fromDisplayGroup(group);
      weekByAxis[axis] = (weekByAxis[axis] ?? 0) + sets;
    });
    expect(weekByAxis, equals(radar.currentSetsByAxis));
    final weekTotal = week.setsByGroup.values.fold<int>(0, (a, b) => a + b);
    final radarTotal =
        radar.currentSetsByAxis.values.fold<int>(0, (a, b) => a + b);
    expect(weekTotal, radarTotal);
    expect(weekTotal, 6);
  });

  test(
      '#442 regresión: los sets custom de una rutina NO-más-reciente cuentan; '
      'targetByGroup sigue saliendo SOLO de la rutina más reciente', () async {
    final repo = MockSessionRepository();

    final sNew = makeSession(
      id: 's-new',
      startedAt: DateTime.utc(2026, 7, 15, 12),
      status: SessionStatus.finished,
      wasFullyCompleted: true,
      routineId: 'rNew',
    );
    final sOld = makeSession(
      id: 's-old',
      startedAt: DateTime.utc(2026, 7, 14, 12),
      status: SessionStatus.finished,
      wasFullyCompleted: true,
      routineId: 'rOld',
    );
    when(() => repo.listByUid('u1')).thenAnswer((_) async => [sNew, sOld]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-new'))
        .thenAnswer((_) async => [
              makeSetLog(id: 'n1', exerciseId: 'c-new', setNumber: 1),
            ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-old'))
        .thenAnswer((_) async => [
              makeSetLog(id: 'o1', exerciseId: 'c-old', setNumber: 1),
              makeSetLog(id: 'o2', exerciseId: 'c-old', setNumber: 2),
            ]);

    final rNew = makeRoutine(id: 'rNew', days: [
      makeDay(slots: [
        makeSlot(exerciseId: 'c-new', muscleGroup: 'chest', targetSets: 4),
      ]),
    ]);
    final rOld = makeRoutine(id: 'rOld', days: [
      makeDay(slots: [
        makeSlot(exerciseId: 'c-old', muscleGroup: 'back', targetSets: 9),
      ]),
    ]);

    final container = ProviderContainer(overrides: [
      sessionRepositoryProvider.overrideWithValue(repo),
      // Catálogo VACÍO: ambos ejercicios sólo resuelven vía slots de rutina.
      exercisesProvider.overrideWith((ref) async => const <Exercise>[]),
      routineByIdProvider('rNew').overrideWith((ref) async => rNew),
      visibleRoutineByIdProvider('rNew').overrideWith((ref) async => rNew),
      visibleRoutineByIdProvider('rOld').overrideWith((ref) async => rOld),
    ]);
    addTearDown(container.dispose);

    final result = await container.read(
      athleteWeekInsightsProvider((uid: 'u1', weekStart: pinnedMonday)).future,
    );

    // Antes del fix: c-old no estaba en los slots de rNew (la única rutina
    // resuelta) → sus 2 sets se descartaban y espalda quedaba ausente.
    expect(result!.setsByGroup[MuscleGroupDisplay.pecho], 1);
    expect(result.setsByGroup[MuscleGroupDisplay.espalda], 2);

    // Contrato de targets INTACTO (QA #373): sólo la rutina de REFERENCIA de
    // la semana (rNew, la de la sesión más reciente de la semana) aporta
    // targets — el target de espalda (9) de rOld NO se filtra.
    expect(result.targetByGroup[MuscleGroupDisplay.pecho], 4);
    expect(
        result.targetByGroup.containsKey(MuscleGroupDisplay.espalda), isFalse);
  });

  test(
      '#442 bordes ART: la sesión del domingo 23:59:59 resuelve via SU rutina '
      'aunque la más reciente del historial sea una rutina desaparecida',
      () async {
    final repo = MockSessionRepository();

    // Dentro: domingo 23:59:59 ART (último instante de la semana pineada).
    final sIn = makeSession(
      id: 's-in',
      startedAt: _startedAtForArt(pinnedMonday
          .add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59))),
      status: SessionStatus.finished,
      wasFullyCompleted: true,
      routineId: 'rOld',
    );
    // Fuera (borde exclusivo): lunes siguiente 00:00 ART — además es la
    // sesión MÁS RECIENTE del historial y su rutina ya no existe.
    final sNextWeek = makeSession(
      id: 's-next',
      startedAt: _startedAtForArt(pinnedMonday.add(const Duration(days: 7))),
      status: SessionStatus.finished,
      wasFullyCompleted: true,
      routineId: 'rGone',
    );
    // Fuera: 1ms antes del lunes 00:00 ART de la semana pineada.
    final sBefore = makeSession(
      id: 's-before',
      startedAt: _startedAtForArt(
          pinnedMonday.subtract(const Duration(milliseconds: 1))),
      status: SessionStatus.finished,
      wasFullyCompleted: true,
      routineId: 'rOld',
    );
    when(() => repo.listByUid('u1'))
        .thenAnswer((_) async => [sNextWeek, sIn, sBefore]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-in'))
        .thenAnswer((_) async => [
              makeSetLog(id: 'i1', exerciseId: 'c-old', setNumber: 1),
            ]);

    final rOld = makeRoutine(id: 'rOld', days: [
      makeDay(slots: [
        makeSlot(exerciseId: 'c-old', muscleGroup: 'back', targetSets: 3),
      ]),
    ]);

    final container = ProviderContainer(overrides: [
      sessionRepositoryProvider.overrideWithValue(repo),
      exercisesProvider.overrideWith((ref) async => const <Exercise>[]),
      // Targets (QA #373): la referencia es la rutina de la sesión más
      // reciente DE LA SEMANA (rOld) — rGone (más reciente del historial)
      // sólo pasa por el resolver de slots, que la degrada a null.
      routineByIdProvider('rOld').overrideWith((ref) async => rOld),
      visibleRoutineByIdProvider('rGone').overrideWith((ref) async => null),
      visibleRoutineByIdProvider('rOld').overrideWith((ref) async => rOld),
    ]);
    addTearDown(container.dispose);

    final result = await container.read(
      athleteWeekInsightsProvider((uid: 'u1', weekStart: pinnedMonday)).future,
    );

    // Sólo la sesión del domingo 23:59:59 ART queda dentro de la semana.
    expect(result!.sessionsCount, 1);
    expect(result.daysTrained[6], isTrue);
    // Antes del fix: la resolución usaba una única rutina "vigente" (rGone,
    // que además ya no existe) → el set custom del domingo se descartaba y
    // espalda quedaba ausente.
    expect(result.setsByGroup[MuscleGroupDisplay.espalda], 1);
    expect(result.setsByGroup.length, 1);
    // Targets de la rutina de referencia de ESTA semana (rOld), no de rGone.
    expect(result.targetByGroup[MuscleGroupDisplay.espalda], 3);
    // Las sesiones fuera de la semana no disparan lecturas de setLogs.
    verifyNever(() => repo.listSetLogs(uid: 'u1', sessionId: 's-next'));
    verifyNever(() => repo.listSetLogs(uid: 'u1', sessionId: 's-before'));
  });
}
