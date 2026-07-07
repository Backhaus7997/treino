import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coach/application/trainer_link_providers.dart'
    show trainerLinksStreamProvider;
import '../../coach/domain/trainer_link_status.dart';
import '../../workout/application/session_providers.dart'
    show finishedInWindowByUidProvider;

/// Result exposed by [inactivosProvider].
///
/// - [inactiveAthleteIds]: IDs of athletes who have NO finished session in the
///   last 14 days (and are active with the trainer).
/// - [inactiveCount]: convenience alias for `inactiveAthleteIds.length`.
class InactivosResult {
  const InactivosResult({
    required this.inactiveAthleteIds,
  });

  final List<String> inactiveAthleteIds;
  int get inactiveCount => inactiveAthleteIds.length;
}

/// Derives the list of inactive athletes for the logged-in trainer.
///
/// **Definition**: an athlete is INACTIVE when they have NO finished session
/// in the last 14 calendar days (UTC). The window is `[todayStart - 14d, todayStart + 1d)`.
///
/// **Security gate**: only athletes with `status == active` are considered.
/// The Firestore `session_shares/{athleteId}` document — written by the
/// `syncSessionShareOnTrainerLink` Cloud Function on `status === 'active'` —
/// is what actually authorises reading an athlete's sessions. The
/// `sharedWithTrainer` flag was never wired (its setter has zero callers in
/// lib/) and always defaults `false`, making the old gate permanently dead.
/// Active status is the correct and authorised gate.
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
    );
  }

  final links = linksAsync.valueOrNull ?? const [];

  // Filter to active athletes only (security gate — see class doc).
  final sharingAthleteIds = links
      .where((l) => l.status == TrainerLinkStatus.active)
      .map((l) => l.athleteId)
      .toSet()
      .toList();

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

  final inactiveIds =
      results.where((r) => !r.hasSession).map((r) => r.athleteId).toList();

  return InactivosResult(
    inactiveAthleteIds: inactiveIds,
  );
});
