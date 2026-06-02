import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workout/application/session_providers.dart'
    show sessionsByUidProvider;
import '../../workout/domain/session.dart';
import '../../workout/domain/session_status.dart';
import '../domain/trainer_link_status.dart';
import 'trainer_link_providers.dart' show trainerLinksStreamProvider;

/// A single entry in the "Entrenaron hoy" list: one finished session per
/// athlete, the most-recent one recorded today (UTC).
class TrainedTodayEntry {
  const TrainedTodayEntry({
    required this.athleteId,
    required this.session,
  });

  final String athleteId;

  /// The athlete's most-recent FINISHED session for today (UTC).
  final Session session;
}

/// Derives the list of athletes who have completed at least one session today.
///
/// - Watches [trainerLinksStreamProvider]; passes through loading/error.
/// - Considers only active links where `sharedWithTrainer == true`.
/// - For each qualifying athlete, watches [sessionsByUidProvider(athleteId)].
///   If all athletes are still loading with no data yet, returns loading.
///   Individual athlete errors are skipped (that athlete is omitted).
/// - Per athlete keeps the most-recent finished session whose `finishedAt`
///   falls on the same UTC calendar day as today.
/// - Returns entries sorted by [Session.finishedAt] descending.
final trainedTodayProvider =
    Provider.autoDispose<AsyncValue<List<TrainedTodayEntry>>>((ref) {
  final linksAsync = ref.watch(trainerLinksStreamProvider);

  // Propagate links loading/error.
  if (linksAsync.isLoading && !linksAsync.hasValue) {
    return const AsyncValue.loading();
  }
  if (linksAsync.hasError && !linksAsync.hasValue) {
    return AsyncValue.error(linksAsync.error!, linksAsync.stackTrace!);
  }

  final links = linksAsync.valueOrNull ?? const [];

  // Deduplicate athlete IDs from active + sharing links.
  final athleteIds = links
      .where(
        (l) =>
            l.status == TrainerLinkStatus.active && l.sharedWithTrainer == true,
      )
      .map((l) => l.athleteId)
      .toSet()
      .toList();

  final now = DateTime.now().toUtc();

  final entries = <TrainedTodayEntry>[];
  bool anyLoading = false;

  for (final athleteId in athleteIds) {
    final sessionsAsync = ref.watch(sessionsByUidProvider(athleteId));

    if (sessionsAsync.isLoading && !sessionsAsync.hasValue) {
      anyLoading = true;
      continue; // will recalculate once data arrives
    }
    if (sessionsAsync.hasError && !sessionsAsync.hasValue) {
      continue; // skip this athlete on error
    }

    final sessions = sessionsAsync.valueOrNull ?? const [];

    // Find the most-recent finished session from today (UTC).
    Session? best;
    for (final s in sessions) {
      if (s.status != SessionStatus.finished) continue;
      final finished = s.finishedAt;
      if (finished == null) continue;
      final utc = finished.toUtc();
      if (utc.year != now.year ||
          utc.month != now.month ||
          utc.day != now.day) {
        continue;
      }
      if (best == null || finished.isAfter(best.finishedAt!)) {
        best = s;
      }
    }

    if (best != null) {
      entries.add(TrainedTodayEntry(athleteId: athleteId, session: best));
    }
  }

  // If every athlete was still loading (and entries is empty), stay loading.
  if (anyLoading && entries.isEmpty) {
    return const AsyncValue.loading();
  }

  // Sort by finishedAt descending.
  entries.sort(
    (a, b) => b.session.finishedAt!.compareTo(a.session.finishedAt!),
  );

  return AsyncValue.data(entries);
});
