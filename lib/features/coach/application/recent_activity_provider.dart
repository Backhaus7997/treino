import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/argentina_time.dart';
import '../../workout/application/session_providers.dart'
    show finishedInWindowByUidProvider;
import '../../workout/domain/session.dart';
import '../domain/trainer_link_status.dart';
import 'trainer_link_providers.dart' show trainerLinksStreamProvider;

/// One entry in the trainer dashboard's "Actividad reciente" feed: a finished
/// session by one of the trainer's athletes within the recent window.
class RecentActivityEntry {
  const RecentActivityEntry({required this.athleteId, required this.session});

  final String athleteId;
  final Session session;
}

/// Days the recent-activity window spans (today + the previous 6 ART days).
const _kRecentActivityDays = 7;

/// Max entries surfaced in the feed.
const _kRecentActivityLimit = 8;

/// A newest-first feed of the trainer's athletes' finished sessions over the
/// last [_kRecentActivityDays] ART days.
///
/// - Considers all `active` links; per-athlete session access is gated by
///   `session_shares` at the rules layer, so non-sharing athletes surface as
///   permission-denied and are skipped (same contract as [trainedTodayProvider]).
/// - The window bounds are ART-day-truncated so the [finishedInWindowByUidProvider]
///   family keys stay stable across builds — a full-precision key would change
///   every frame and spin an infinite rebuild loop.
/// - Complements "Entrenaron hoy" (a today snapshot) with a rolling timeline.
final recentActivityProvider =
    Provider.autoDispose<AsyncValue<List<RecentActivityEntry>>>((ref) {
  final linksAsync = ref.watch(trainerLinksStreamProvider);

  if (linksAsync.isLoading && !linksAsync.hasValue) {
    return const AsyncValue.loading();
  }
  if (linksAsync.hasError && !linksAsync.hasValue) {
    return AsyncValue.error(linksAsync.error!, linksAsync.stackTrace!);
  }

  final links = linksAsync.valueOrNull ?? const [];
  final athleteIds = links
      .where((l) => l.status == TrainerLinkStatus.active)
      .map((l) => l.athleteId)
      .toSet()
      .toList();

  // ART-day-truncated window [from, to): today + the previous 6 ART days.
  // ART midnight is 03:00 UTC (UTC-3); the value is constant within an ART day
  // → stable family key.
  final now = argentinaNow();
  final todayStart =
      DateTime.utc(now.year, now.month, now.day).add(argentinaUtcOffset);
  final to = todayStart.add(const Duration(days: 1));
  final from =
      todayStart.subtract(const Duration(days: _kRecentActivityDays - 1));

  final entries = <RecentActivityEntry>[];
  bool anyLoading = false;

  for (final athleteId in athleteIds) {
    final sessionsAsync = ref.watch(finishedInWindowByUidProvider(
        (athleteId: athleteId, from: from, to: to)));

    if (sessionsAsync.isLoading && !sessionsAsync.hasValue) {
      anyLoading = true;
      continue;
    }
    if (sessionsAsync.hasError && !sessionsAsync.hasValue) {
      continue; // athlete not sharing → permission-denied → skip
    }

    for (final s in sessionsAsync.valueOrNull ?? const <Session>[]) {
      if (!s.countsAsWorkout || s.finishedAt == null) continue;
      entries.add(RecentActivityEntry(athleteId: athleteId, session: s));
    }
  }

  // Wait for EVERY athlete's read to resolve before emitting: this feed is
  // sorted newest-first, so a partial emission could momentarily show entries
  // out of order. Denied reads error (not loading) and are already skipped, so
  // this cannot hang on a non-sharing athlete.
  if (anyLoading) {
    return const AsyncValue.loading();
  }

  entries
      .sort((a, b) => b.session.finishedAt!.compareTo(a.session.finishedAt!));

  return AsyncValue.data(
    entries.length > _kRecentActivityLimit
        ? entries.sublist(0, _kRecentActivityLimit)
        : entries,
  );
});
