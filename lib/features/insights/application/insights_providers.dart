import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/argentina_time.dart';
import '../../../core/utils/weekly_streak_calculator.dart';
import '../../workout/application/exercise_providers.dart';
import '../../workout/application/plan_progress.dart';
import '../../workout/application/routine_providers.dart';
import '../../workout/application/session_providers.dart';
import '../../workout/application/weekly_streak_providers.dart';
import '../../workout/domain/routine.dart';
import '../../workout/domain/session.dart';
import '../../workout/domain/session_status.dart';
import '../domain/muscle_group.dart';
import '../domain/weekly_insights.dart';
import 'routine_slot_groups.dart';

/// [UX-week-day-selector] Family key for [athleteWeekInsightsProvider].
/// Explicit [uid] (NOT `currentUidProvider`) and explicit [weekStart] (must
/// already be normalized to a Monday 00:00 local via [mondayOfWeek]) — same
/// pattern `athleteDayInsightsProvider` uses so the SAME provider can serve
/// the athlete's own paged week view.
typedef AthleteWeekInsightsKey = ({String uid, DateTime weekStart});

/// [UX-week-day-selector] Per-week aggregate for [key.uid], for the week
/// starting [key.weekStart] (Monday 00:00 local) — generalizes the old
/// hardwired "current week only" `weeklyInsightsProvider` so the SEMANA card
/// can page to past weeks. `streak` and `monthSessionsCount` are computed
/// from the FULL session history regardless of which week is shown (they are
/// not week-scoped concepts), matching the original provider's semantics.
final athleteWeekInsightsProvider = FutureProvider.autoDispose
    .family<WeeklyInsights?, AthleteWeekInsightsKey>((ref, key) async {
  if (key.uid.isEmpty) return null;

  // Antes de cualquier await: usar `ref` después de un async gap es inseguro
  // cuando el provider se recomputa a mitad de vuelo (misma regla que
  // `unifiedRoutinesProvider`).
  final weeklyTarget = ref.watch(weeklyStreakTargetProvider);

  final repo = ref.read(sessionRepositoryProvider);

  // Rango de semana — lunes 00:00 local (ya normalizado por el caller) hasta
  // el siguiente lunes (exclusivo). Aritmética de calendario (no Duration)
  // para que el borde caiga en medianoche local incluso atravesando un
  // cambio de horario (DST).
  final weekStart = DateTime.utc(
    key.weekStart.year,
    key.weekStart.month,
    key.weekStart.day,
  );
  final weekEndExclusive =
      DateTime.utc(weekStart.year, weekStart.month, weekStart.day + 7);
  final now = argentinaNow();

  // Todas las sessions del usuario (listByUid ya viene ordenado DESC por
  // startedAt en SessionRepository).
  final allSessions = await repo.listByUid(key.uid);
  final mostRecentSession = allSessions.isNotEmpty ? allSessions.first : null;

  // Filtro a la semana pedida + finished.
  final weekSessions = allSessions.where((s) {
    final started = toArgentina(s.startedAt);
    return !started.isBefore(weekStart) &&
        started.isBefore(weekEndExclusive) &&
        s.countsAsWorkout;
  }).toList();

  // Días entrenados (0=lun..6=dom).
  final daysTrained = List<bool>.filled(7, false);
  for (final s in weekSessions) {
    final dayIndex = toArgentina(s.startedAt).weekday - DateTime.monday;
    if (dayIndex >= 0 && dayIndex < 7) {
      daysTrained[dayIndex] = true;
    }
  }

  // Catálogo de ejercicios → index por id para lookup O(1).
  final exercises = await ref.watch(exercisesProvider.future);
  final byId = {for (final e in exercises) e.id: e};

  // Rutina de REFERENCIA para targets (QA #373): la de la sesión más
  // reciente DE LA SEMANA pedida (weekSessions preserva el orden DESC de
  // listByUid → first = más reciente), con fallback a la última del
  // historial solo cuando la semana está vacía (típico: semana calendario
  // recién empezada, o cambio de plan sin estrenarlo).
  //
  // QA #480: visibleRoutineByIdProvider, NO routineByIdProvider — una rutina
  // borrada o con acceso revocado degrada a `null` (→ camino "sin target" de
  // abajo, las progress bars ya lo soportan) en vez de propagar
  // permission-denied y tirar la card SEMANA + Volumen por grupo enteras al
  // error state. Era el ÚNICO fetch de rutina sin guarda que quedaba acá:
  // el fallback de grupos ya degrada vía slotMuscleGroupsForSessions (#442).
  // Fallas transientes SÍ propagan — ver RoutineRepository.getByIdIfVisible.
  final referenceRoutineId = weekSessions.isNotEmpty
      ? weekSessions.first.routineId
      : mostRecentSession?.routineId;
  final routine = (referenceRoutineId != null && referenceRoutineId.isNotEmpty)
      ? await ref.watch(visibleRoutineByIdProvider(referenceRoutineId).future)
      : null;

  // Fallback exerciseId → muscleGroup para ejercicios custom ausentes del
  // catálogo, cuyos setLogs sólo guardan exerciseId (SetLog no denormaliza
  // el grupo). Resuelve la rutina de CADA sesión de la semana — no sólo una:
  // una semana puede abarcar un cambio de plan (o el paging aterrizar en
  // semanas de una rutina ya reemplazada), y asumir una única rutina
  // descartaba en silencio los sets custom de las otras (#442). Resolver
  // COMPARTIDO con muscle distribution / month radar, para que las
  // superficies no puedan volver a divergir; a diferencia del fetch de
  // targets de arriba, degrada rutinas borradas/revocadas sin tirar la card
  // entera (ver [slotMuscleGroupsForSessions]). La sesión más reciente del
  // historial se antepone para que los custom ad-hoc que sólo el plan
  // vigente conoce sigan resolviendo, con la misma precedencia
  // más-reciente-primero que el scan del radar.
  final slotGroupById = await slotMuscleGroupsForSessions(
    ref,
    [if (mostRecentSession != null) mostRecentSession, ...weekSessions],
  );

  // setsByGroup — los setLogs de cada session de la semana. Las lecturas por
  // sesión se paralelizan con Future.wait (una subcolección por sesión) para
  // colapsar N round-trips seriales en un batch.
  final setsByGroup = <MuscleGroupDisplay, int>{};
  final logsPerSession = await Future.wait(
    weekSessions.map((s) => repo.listSetLogs(uid: key.uid, sessionId: s.id)),
  );
  for (final logs in logsPerSession) {
    for (final log in logs) {
      // Catálogo público primero; si el id es custom (ausente), resolver vía
      // el muscleGroup denormalizado del slot de la rutina.
      final groupRaw =
          byId[log.exerciseId]?.muscleGroup ?? slotGroupById[log.exerciseId];
      final group = groupRaw?.toDisplayGroup();
      if (group != null) {
        setsByGroup[group] = (setsByGroup[group] ?? 0) + 1;
      }
    }
  }

  // targetByGroup — usa el `muscleGroup` ya denormalizado del slot (correcto
  // para ejercicios custom y sin depender de que el catálogo esté completo).
  // Si el usuario nunca entrenó o la rutina no se encuentra, queda vacío y las
  // progress bars se renderizan sin target.
  //
  // QA #373: en un plan periodizado (Model B) los slots difieren por semana —
  // sumar TODOS los day.slots sobreestimaba el denominador con sets de
  // semanas que no corresponden. El target ahora cuenta SOLO los slots
  // presentes en la semana del plan que esta semana calendario representa
  // (mismo criterio isPresentInWeek que planProgressProvider). Para planes
  // sin periodización la mask vacía hace isPresentInWeek == true siempre →
  // comportamiento idéntico al anterior.
  final targetByGroup = <MuscleGroupDisplay, int>{};
  if (routine != null) {
    final planWeek = _planWeekFor(routine, weekSessions, allSessions);
    for (final day in routine.days) {
      for (final slot in day.slots) {
        if (!slot.isPresentInWeek(planWeek)) continue;
        final group = slot.muscleGroup.toDisplayGroup();
        if (group != null) {
          targetByGroup[group] = (targetByGroup[group] ?? 0) + slot.targetSets;
        }
      }
    }
  }

  // streak — SEMANAS consecutivas en las que el atleta cumplió el objetivo de
  // días de su rutina activa. Reemplaza a la racha por día de `computeStreak`
  // (ADR-WRS-08); la semántica y por qué la semana en curso no corta están en
  // `computeWeeklyStreak`.
  // NB: bucketea en el frame ART internamente (#411). Su `now` es un instante
  // REAL (se normaliza con `.toUtc()` adentro) — pasarle el `now` ya framed en
  // ART de más arriba sería doble corrimiento, así que lo dejamos caer a
  // `DateTime.now()`, igual que el resto de los callers.
  final streak = computeWeeklyStreak(
    sessions: allSessions,
    weeklyTarget: weeklyTarget,
  );

  // monthSessionsCount — sesiones finished en el mes calendario actual.
  // ADR-WRS-03: mes calendario ARGENTINA (mismo frame que el resto de Insights),
  // NOT ventana de 30 días.
  final monthSessionsCount = allSessions.where((s) {
    if (!s.countsAsWorkout) return false;
    final local = toArgentina(s.startedAt);
    return local.year == now.year && local.month == now.month;
  }).length;

  // Bug fix (abandoned-session-streak-reports): "entrenó alguna vez" se
  // deriva de la MISMA lectura `allSessions` de arriba — sin fetch extra.
  // Desacopla el hub de reportes históricos del `_EmptyState` de onboarding
  // en insights_screen.dart: una semana en 0 no implica cuenta nueva.
  final hasEverCompletedAnyWorkout = allSessions.any((s) => s.countsAsWorkout);

  return WeeklyInsights(
    weekStart: weekStart,
    weekEnd: weekEndExclusive.subtract(const Duration(milliseconds: 1)),
    daysTrained: daysTrained,
    sessionsCount: weekSessions.length,
    // Hardcoded 5 — decisión 5. Refinar cuando Coach exponga plannedDays.
    plannedSessionsCount: 5,
    setsByGroup: setsByGroup,
    targetByGroup: targetByGroup,
    streak: streak,
    monthSessionsCount: monthSessionsCount,
    hasEverCompletedAnyWorkout: hasEverCompletedAnyWorkout,
  );
});

/// Calcula los agregados de la SEMANA ACTUAL del usuario logueado. Delgado
/// wrapper sobre [athleteWeekInsightsProvider] con `weekStart` fijo a "esta
/// semana" — mantenido para consumers existentes (home's `EstaSemanaCard`)
/// que no necesitan pagear semanas. autoDispose: se re-evalúa cada vez que
/// se monta la pantalla.
final weeklyInsightsProvider =
    FutureProvider.autoDispose<WeeklyInsights?>((ref) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return null;

  final weekStart = mondayOfWeek(argentinaNow());
  return ref.watch(
    athleteWeekInsightsProvider((uid: uid, weekStart: weekStart)).future,
  );
});

// ── Week helpers ──────────────────────────────────────────────────────────────

/// [UX-week-day-selector] Monday 00:00 local of the week containing [now].
/// Public (was `_mondayOfWeek`) so the SEMANA card's paging logic
/// (`insights_screen.dart`) can compute prior/next week boundaries with the
/// same calendar-arithmetic, DST-safe rule.
/// La implementación vive en `core/utils/argentina_time.dart` como
/// [mondayOfWeekArt] — `computeWeeklyStreak` la necesita y `core/` no puede
/// importar una feature. Este alias se queda porque es el punto de import de
/// todo lo que ya lo usaba (`insights_screen`, `session_recognition`,
/// `volume_by_group_screen`): mover la definición no tiene por qué mover los
/// imports.
DateTime mondayOfWeek(DateTime now) => mondayOfWeekArt(now);

/// QA #373: qué semana del PLAN representa la semana calendario pedida.
///
/// 1. Si la semana tiene sesiones de [routine], la más reciente manda: su
///    `weekNumber` (0-based, el mismo que persiste el player y consume
///    planProgressProvider) ES la semana del plan que el atleta cursaba en
///    esa semana calendario — correcto también al paginar semanas pasadas.
/// 2. Semana sin sesiones de la rutina (típico: semana calendario recién
///    empezada, o el atleta cambió de plan sin estrenarlo): la semana activa
///    derivada del plan completo, con el MISMO derive que
///    planProgressProvider (completed + requiredPairs por isPresentInWeek).
///    El armado de requiredPairs espeja session_providers.dart
///    (REQ-WPRES-022) — extraer un helper compartido cuando #442 aterrice,
///    para no ensanchar ese archivo mientras está en vuelo.
int _planWeekFor(
  Routine routine,
  List<Session> weekSessions,
  List<Session> allSessions,
) {
  for (final s in weekSessions) {
    if (s.routineId == routine.id) return s.weekNumber;
  }

  final completed = allSessions
      .where(
        (s) =>
            s.routineId == routine.id &&
            s.status == SessionStatus.finished &&
            s.wasFullyCompleted,
      )
      .map((s) => (week: s.weekNumber, day: s.dayNumber))
      .toSet();
  final dayNumbers = routine.days.map((d) => d.dayNumber).toList();
  final requiredPairs = <CompletedKey>{};
  for (var w = 0; w < routine.numWeeks; w++) {
    for (final d in routine.days) {
      if (d.slots.any((s) => s.isPresentInWeek(w))) {
        requiredPairs.add((week: w, day: d.dayNumber));
      }
    }
  }
  return derivePlanProgress(
    completed,
    dayNumbers,
    routine.numWeeks,
    requiredPairs: requiredPairs,
  ).activeWeek;
}
