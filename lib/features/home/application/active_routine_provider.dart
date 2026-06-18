import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../workout/application/user_routines_providers.dart';
import '../../workout/domain/routine.dart';

/// Resolves the athlete's currently active self-created routine.
///
/// Used by [todaysRoutineProvider] to disambiguate the multi-rutina case:
/// when the user has 2+ self-created routines and no trainer-assigned plan,
/// only the one explicitly marked active drives the home card.
///
/// Returns null when:
///   * The user has no `activeRoutineId` set (multi-rutina without selection,
///     home falls back to the empty CTA),
///   * The marked id doesn't match any active user-created routine (e.g. the
///     routine was archived after being marked — stale pointer is ignored).
///
/// When the user has a single user-created routine, callers should treat it
/// as auto-active without consulting this provider — that's PR#1 behavior
/// preserved in [todaysRoutineProvider].
final activeRoutineProvider = Provider.autoDispose<Routine?>((ref) {
  final uid = ref.watch(currentUidProvider) ?? '';
  if (uid.isEmpty) return null;

  final profile = ref.watch(userProfileProvider).valueOrNull;
  final activeId = profile?.activeRoutineId;
  if (activeId == null || activeId.isEmpty) return null;

  final routines = ref.watch(userCreatedRoutinesProvider(uid)).valueOrNull;
  if (routines == null) return null;

  for (final r in routines) {
    if (r.id == activeId) return r;
  }
  return null;
});
