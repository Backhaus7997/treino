import '../../../core/utils/argentina_time.dart';

/// Read-time decay for the denormalized `racha` on `userPublicProfiles` (#552).
///
/// SEMANTIC DECISION (#552): everywhere the app shows a "racha" it means the
/// CURRENT streak as of today in the Argentina calendar frame — the same value
/// `computeStreak` returns. The stored `racha` field is a snapshot taken the
/// last time the athlete finished a workout: it is exact while the athlete's
/// streak is alive, but it never decays on its own — an athlete who stopped
/// training keeps their last value forever, which is how PERFIL (live
/// `computeStreak` → 0) and RANKINGS (stale stored 1) came to disagree.
///
/// A stored streak written on day D remains the correct CURRENT streak on day
/// D and on day D+1 (computeStreak's yesterday-grace: a streak whose last
/// workout was yesterday is still alive). From D+2 onward, with no new
/// workout — and therefore no new stamp — the current streak is 0 by
/// definition. So freshness collapses to: is [rachaUpdatedAt]'s ART calendar
/// date today or yesterday?
///
/// [rachaUpdatedAt] is the instant `racha` was last recomputed from a
/// qualifying workout (stamped by `UserPublicProfileRepository.updateCounters`
/// at finish time, or by the backfill script from the newest completed
/// session's `startedAt`). A `null` stamp is a legacy doc written before this
/// field existed: we pass the raw value through unchanged (pre-#552 behavior)
/// instead of mass-zeroing every board until `backfill_racha_freshness.js`
/// runs. A session that starts before ART midnight and finishes after it
/// stamps one day late — the {today, yesterday} tolerance absorbs exactly
/// that one-day skew.
///
/// [now] is a REAL instant (any flag) — normalized with `.toUtc()` internally,
/// same contract as `computeStreak`. Do NOT pass `argentinaNow()`.
int effectiveRacha({
  required int? racha,
  required DateTime? rachaUpdatedAt,
  required DateTime now,
}) {
  final raw = racha ?? 0;
  if (rachaUpdatedAt == null) return raw;

  final todayArt = toArgentina(now.toUtc());
  final today = DateTime.utc(todayArt.year, todayArt.month, todayArt.day);
  final stampArt = toArgentina(rachaUpdatedAt.toUtc());
  final stampDay = DateTime.utc(stampArt.year, stampArt.month, stampArt.day);

  final daysOld = today.difference(stampDay).inDays;
  // 0 = stamped today, 1 = stamped yesterday (grace day). Negative = the
  // stamp reads as "future" (device clock behind the server timestamp that
  // wrote it) — it was just written, so it is fresh by construction. Only a
  // stamp 2+ ART days old means the streak is no longer current.
  return daysOld <= 1 ? raw : 0;
}
