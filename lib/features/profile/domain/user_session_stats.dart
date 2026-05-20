import 'package:flutter/foundation.dart';

/// Aggregate stats for the currently signed-in user's own profile screen.
///
/// Computed by [userSessionStatsProvider].
/// Hand-written @immutable (not Freezed) — ADR-WRS-07.
@immutable
class UserSessionStats {
  const UserSessionStats({
    required this.totalSessions,
    required this.totalVolumeKg,
    required this.streak,
  });

  /// Count of all finished sessions across the user's history.
  final int totalSessions;

  /// Sum of [Session.totalVolumeKg] for all finished sessions.
  final double totalVolumeKg;

  /// Current consecutive training streak (days), per ADR-WRS-02.
  final int streak;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserSessionStats &&
          runtimeType == other.runtimeType &&
          totalSessions == other.totalSessions &&
          totalVolumeKg == other.totalVolumeKg &&
          streak == other.streak;

  @override
  int get hashCode =>
      totalSessions.hashCode ^ totalVolumeKg.hashCode ^ streak.hashCode;
}
