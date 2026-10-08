import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart';
import '../../workout/application/assigned_routine_providers.dart';
import '../../workout/application/routine_providers.dart' show routinesProvider;
import '../../workout/application/session_providers.dart'
    show currentUidProvider, sessionsByUidProvider;
import '../../workout/application/user_routines_providers.dart';
import '../../workout/domain/plan_advance.dart';
import '../../workout/domain/routine.dart';
import '../../workout/domain/routine_day.dart';
import '../../workout/domain/routine_selection.dart';
import '../../workout/domain/session.dart';

/// Resolved "what to train today" snapshot for the home `EmpezarEntrenamientoCard`.
///
/// Pure data record — UI computes display strings (heroLabel, muscle subtitle,
/// duration, exercise count) from these fields via the domain helpers.
typedef TodaysRoutine = ({
  Routine routine,
  RoutineDay day,
  int dayNumber, // 1-based, matches RoutineDay.dayNumber
  int weekNumber, // 0-based, advances on day rollover for periodized plans
});

/// Resolves the routine + day the athlete should train next, applying the
/// priority + progress-based day calculation we agreed on in the home card
/// redesign (decision log 2026-06-18):
///
///   PRIORITY
///   0. Explicit active marker (`UserProfile.activeRoutineId`) resolved
///      against the UNIFIED list — trainer-assigned AND self-created
///      (workout redesign slice 1, 2026-07-27: coach plans can be marked
///      active too, and auto-activa/lazy adoption keeps the marker set for
///      almost every user). A stale id falls through to the legacy chain.
///   1. Trainer-assigned plan (any in `assignedRoutinesProvider`). Picks
///      the newest if multiple — repo already orders desc by `createdAt`.
///   2. Single self-created routine (`userCreatedRoutinesProvider.length == 1`).
///   3. Multi self-created → the routine marked as active in
///      `UserProfile.activeRoutineId`. PR#2 (active-routine marker).
///   4. Returns null — multi-rutina without an active marker. Home falls
///      back to the empty CTA + nudges the user to mark one via
///      the unified RUTINAS section overflow menu.
///
///   Tiers 1-4 are the pre-slice-1 chain, kept VERBATIM as the fallback for
///   legacy users whose `activeRoutineId` is still null (or stale).
///
///   DAY CALCULATION (progress-based)
///   * Looks at the latest FINISHED session for the resolved routine.
///   * nextDayNumber = (lastDayNumber % numDays) + 1 — rolls Día 5 → Día 1.
///   * weekNumber rolls only when day wraps: stays on the same week as long
///     as `lastDayNumber < numDays`; advances to `(lastWeek + 1) % numWeeks`
///     on rollover. First session ever: dayNumber 1, weekNumber 0.
///
///   SKIPPED DAYS
///   * Pure last-completed + 1. If the athlete skips Día 2 and only ever
///     does Día 1 and Día 3, the next will be Día 4 — not the missed Día 2.
///     Matches Hevy/Strong, intuitive for users who occasionally miss days.
///     Manual override still available via the day selector in routine_detail.
///
/// Returns null when:
///   * uid is empty/unauthenticated
///   * No routine matches the priority chain
///   * Resolved routine has no days (defensive)
final todaysRoutineProvider = FutureProvider.autoDispose<TodaysRoutine?>(
  (ref) async {
    final uid = ref.watch(currentUidProvider) ?? '';
    if (uid.isEmpty) return null;

    // Tier 0: explicit active marker, resolved against BOTH lists. `select`
    // keeps this subscription scoped to the id — unrelated profile writes
    // (racha, settings) don't recompute the card.
    final activeId = ref.watch(
      userProfileProvider.select((a) => a.valueOrNull?.activeRoutineId),
    );

    final assigned = await ref.watch(assignedRoutinesProvider(uid).future);
    // La lista de auto-creadas se resuelve siempre porque `resolveActiveRoutineId`
    // la necesita para el marcador explícito y para los tiers 2/3. El provider
    // está cacheado, así que no es una lectura extra costosa.
    final selfCreated =
        await ref.watch(userCreatedRoutinesProvider(uid).future);

    // La prioridad vive en `resolveActiveRoutineId`
    // (workout/domain/routine_selection.dart) porque el cliente watchOS la
    // reimplementa en Swift y los fixtures de
    // `conformance/routine_selection.json` son el contrato entre ambas. Acá
    // solo se resuelven las entradas y se traduce el id de vuelta a Routine.
    var resolvedId = resolveActiveRoutineId(
      activeRoutineId: activeId,
      assignedIds: [for (final r in assigned) r.id],
      selfCreatedIds: [for (final r in selfCreated) r.id],
    );

    // El catálogo se carga SÓLO si hace falta, y hace falta en un único caso:
    // hay marcador y no matcheó contra los planes del atleta. Ahí el marcador
    // puede ser una plantilla del sistema que el atleta eligió SEGUIR sin
    // copiarla — o un id obsoleto de verdad, que sigue cayendo a la cadena.
    //
    // Watchearlo siempre le costaría a TODA la Home una lectura de las 7
    // plantillas que la enorme mayoría no necesita: quien tiene plan del PF o
    // rutina propia ya resolvió arriba. Un `watch` condicional es legal en
    // Riverpod — el set de dependencias cambia entre builds y el provider se
    // recomputa cuando corresponde.
    List<Routine> catalog = const [];
    final markerFellThrough =
        activeId != null && activeId.isNotEmpty && resolvedId != activeId;
    if (markerFellThrough) {
      catalog = await ref.watch(routinesProvider.future);
      resolvedId = resolveActiveRoutineId(
        activeRoutineId: activeId,
        assignedIds: [for (final r in assigned) r.id],
        selfCreatedIds: [for (final r in selfCreated) r.id],
        catalogIds: [for (final r in catalog) r.id],
      );
    }

    Routine? routine;
    if (resolvedId != null) {
      for (final r in assigned) {
        if (r.id == resolvedId) {
          routine = r;
          break;
        }
      }
      routine ??= () {
        for (final r in selfCreated) {
          if (r.id == resolvedId) return r;
        }
        for (final r in catalog) {
          if (r.id == resolvedId) return r;
        }
        return null;
      }();
    }

    if (routine == null || routine.days.isEmpty) return null;

    // Find the most recent FINISHED session for THIS routine (sessions are
    // already ordered startedAt desc by the repo).
    final sessions = await ref.watch(sessionsByUidProvider(uid).future);
    Session? lastFinished;
    for (final s in sessions) {
      if (s.routineId == routine.id && s.countsAsWorkout) {
        lastFinished = s;
        break;
      }
    }

    // La aritmética vive en `nextPlanPosition` (workout/domain/plan_advance.dart)
    // porque el cliente watchOS la reimplementa en Swift y los fixtures
    // compartidos de `conformance/plan_advance.json` son el contrato entre las
    // dos implementaciones. Acá solo se resuelven las entradas.
    final numDays = routine.days.length;
    final position = nextPlanPosition(
      lastFinished: lastFinished == null
          ? null
          : (
              dayNumber: lastFinished.dayNumber,
              weekNumber: lastFinished.weekNumber,
            ),
      numDays: numDays,
      numWeeks: routine.numWeeks,
    );
    final nextDayNumber = position.dayNumber;
    final weekNumber = position.weekNumber;

    // Resolve the RoutineDay. Defensive against non-contiguous dayNumbers
    // (shouldn't happen, but a hand-edited Firestore doc could).
    RoutineDay? day;
    for (final d in routine.days) {
      if (d.dayNumber == nextDayNumber) {
        day = d;
        break;
      }
    }
    day ??= routine.days.first;

    return (
      routine: routine,
      day: day,
      dayNumber: nextDayNumber,
      weekNumber: weekNumber,
    );
  },
);
