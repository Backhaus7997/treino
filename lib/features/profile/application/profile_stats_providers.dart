import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/streak_calculator.dart';
import '../../workout/application/session_providers.dart';
import '../../workout/domain/session.dart';
import '../domain/user_session_stats.dart';

/// Computes aggregate stats for the currently signed-in user's own profile.
///
/// Returns zero stats for unauthenticated users (null uid) — no Firestore reads.
/// autoDispose: re-evaluated each time ProfileScreen mounts.
final userSessionStatsProvider =
    FutureProvider.autoDispose<UserSessionStats>((ref) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    return const UserSessionStats(
      totalSessions: 0,
      totalVolumeKg: 0,
      streak: 0,
    );
  }

  final repo = ref.watch(sessionRepositoryProvider);
  final sessions = await repo.listByUid(uid);

  final finished = sessions.where((s) => s.countsAsWorkout).toList();

  return UserSessionStats(
    totalSessions: finished.length,
    totalVolumeKg: finished.fold<double>(0, (sum, s) => sum + s.totalVolumeKg),
    streak: computeStreak(sessions),
  );
});
