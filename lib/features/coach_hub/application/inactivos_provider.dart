import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coach/application/trainer_link_providers.dart'
    show trainerLinksStreamProvider;
import '../../coach/domain/trainer_link_status.dart';
import '../../workout/application/session_providers.dart'
    show finishedInWindowByUidProvider;

/// Result exposed by [inactivosProvider].
///
/// - [inactiveAthleteIds]: IDs of athletes who have NO finished session in the
///   last 14 days (and are active + sharing with the trainer).
/// - [inactiveCount]: convenience alias for `inactiveAthleteIds.length`.
/// - [totalSharingCount]: total active + sharing athletes (denominator for the
///   "N de M" disclaimer in the UI).
class InactivosResult {
  const InactivosResult({
    required this.inactiveAthleteIds,
    required this.totalSharingCount,
  });

  final List<String> inactiveAthleteIds;
  final int totalSharingCount;
  int get inactiveCount => inactiveAthleteIds.length;
}

/// Derives the list of inactive athletes for the logged-in trainer.
///
/// **Definition**: an athlete is INACTIVE when they have NO finished session
/// in the last 14 calendar days (UTC). The window is `[todayStart - 14d, todayStart + 1d)`.
///
/// **Security gate**: only athletes with `status == active && sharedWithTrainer == true`
/// are considered. Athletes who haven't opted in are invisible — intentional.
///
/// **Stable key**: the window boundaries are day-truncated so the
/// [finishedInWindowByUidProvider] family key is stable between builds.
///
/// **Fan-out pattern**: mirrors [trainedTodayProvider] in
/// `lib/features/coach/application/trained_today_provider.dart`.
final inactivosProvider =
    FutureProvider.autoDispose<InactivosResult>((ref) async {
  final linksAsync = ref.watch(trainerLinksStreamProvider);

  // Propagate loading/error states.
  if (linksAsync.isLoading && !linksAsync.hasValue) {
    return const InactivosResult(
      inactiveAthleteIds: [],
      totalSharingCount: 0,
    );
  }

  final links = linksAsync.valueOrNull ?? const [];

  // Filter to active + sharing athletes only (security gate).
  final sharingAthleteIds = links
      .where(
        (l) =>
            l.status == TrainerLinkStatus.active && l.sharedWithTrainer == true,
      )
      .map((l) => l.athleteId)
      .toSet()
      .toList();

  final totalSharingCount = sharingAthleteIds.length;

  // Day-truncated stable window boundaries.
  final now = DateTime.now().toUtc();
  final todayStart = DateTime.utc(now.year, now.month, now.day);
  final from = todayStart.subtract(const Duration(days: 14));
  final to = todayStart.add(const Duration(days: 1));

  // Fan-out: check each athlete's session window in parallel.
  final futures = sharingAthleteIds.map((athleteId) async {
    final windowKey = (athleteId: athleteId, from: from, to: to);
    final sessionsAsync =
        await ref.watch(finishedInWindowByUidProvider(windowKey).future);
    return (athleteId: athleteId, hasSession: sessionsAsync.isNotEmpty);
  });

  final results = await Future.wait(futures);

  final inactiveIds = results
      .where((r) => !r.hasSession)
      .map((r) => r.athleteId)
      .toList();

  return InactivosResult(
    inactiveAthleteIds: inactiveIds,
    totalSharingCount: totalSharingCount,
  );
});
