import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coach/application/trainer_link_providers.dart'
    show trainerLinksStreamProvider;
import '../../coach/domain/trainer_link_status.dart';
import '../../workout/application/assigned_routine_providers.dart'
    show assignedRoutinesProvider;
import '../../workout/application/session_providers.dart'
    show finishedInWindowByUidProvider;
import '../../workout/domain/routine.dart';
import '../../workout/domain/routine_status.dart';
import '../presentation/sections/alumnos/resumen_metrics.dart'
    show ResumenMetrics;

/// Derives the aggregate adherencia (%) across all active+sharing athletes
/// for the logged-in trainer.
///
/// **Formula**: same as [ResumenMetrics.compute] — reused, not re-implemented.
///   adherencia30dPct = completedSessions_last_30d / (weeklyTarget * 30/7) * 100
///
/// **Aggregate**: arithmetic average of per-athlete non-null values.
///   Returns `null` when NO athlete has an active plan (weeklyTarget == 0 for all).
///
/// **Security gate**: only athletes with `status == active` are considered.
///   The Firestore `session_shares/{athleteId}` document — written by the
///   `syncSessionShareOnTrainerLink` Cloud Function on `status === 'active'` —
///   is what actually authorises reading an athlete's sessions. The
///   `sharedWithTrainer` flag was never wired (its setter has zero callers in
///   lib/) and always defaults `false`, making the old `&& sharedWithTrainer`
///   gate permanently dead. Active status is the correct and authorised gate.
///
/// **Stable key**: window boundaries are day-truncated UTC so the
///   [finishedInWindowByUidProvider] family key is stable between builds
///   (avoids infinite-rebuild loop — critical lesson from PR1).
///
/// **Fan-out cost**: O(N×2) reads per mount — N sessions reads + N routines reads.
///   Bounded 30-day window limits each sessions query. Acceptable for typical
///   trainer rosters (≤20 athletes).
final aggregateAdherenceProvider =
    FutureProvider.autoDispose<double?>((ref) async {
  final linksAsync = ref.watch(trainerLinksStreamProvider);

  // Propagate loading state without blocking: return null while links load.
  if (linksAsync.isLoading && !linksAsync.hasValue) {
    return null;
  }

  final links = linksAsync.valueOrNull ?? const [];

  // Filter to active athletes only (security gate — see class doc).
  final sharingAthleteIds = links
      .where((l) => l.status == TrainerLinkStatus.active)
      .map((l) => l.athleteId)
      .toSet()
      .toList();

  // No active athletes → no data.
  if (sharingAthleteIds.isEmpty) return null;

  // Day-truncated stable window boundaries (30-day adherence window).
  // NEVER use DateTime.now() at full precision as a .family key — it creates
  // a new key every build → infinite rebuild → pumpAndSettle hang in CI.
  final now = DateTime.now().toUtc();
  final todayStart = DateTime.utc(now.year, now.month, now.day);
  final from = todayStart.subtract(const Duration(days: 30));
  final to = todayStart.add(const Duration(days: 1));

  // Fan-out: compute per-athlete adherencia in parallel.
  final futures = sharingAthleteIds.map((athleteId) async {
    // 1. Bounded 30-day sessions window (reuses PR1's finishedInWindowByUidProvider).
    final windowKey = (athleteId: athleteId, from: from, to: to);
    final sessions =
        await ref.watch(finishedInWindowByUidProvider(windowKey).future);

    // 2. Active routine's weeklyTarget (days.length of first active plan).
    final routines =
        await ref.watch(assignedRoutinesProvider(athleteId).future);
    final Routine? activeRoutine =
        routines.where((r) => r.status == RoutineStatus.active).firstOrNull;

    final int weeklyTarget = activeRoutine?.days.length ?? 0;

    // 3. Compute adherencia via ResumenMetrics (reuse — do NOT inline the formula).
    final metrics = ResumenMetrics.compute(
      sessions: sessions,
      measurements: const [], // not needed for adherencia30dPct
      weeklyTarget: weeklyTarget,
      now: now,
    );

    return metrics.adherencia30dPct; // null when weeklyTarget == 0
  });

  final perAthleteValues = await Future.wait(futures);

  // Average the non-null values.
  final nonNull = perAthleteValues.whereType<double>().toList();
  if (nonNull.isEmpty) return null;

  return nonNull.reduce((a, b) => a + b) / nonNull.length;
});
