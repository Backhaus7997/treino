import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workout/application/unified_routines_providers.dart'
    show unifiedRoutinesProvider;

export '../../workout/application/assigned_routine_providers.dart'
    show assignedRoutinesProvider;

/// Synchronous count of the athlete's active routines, derived from
/// [unifiedRoutinesProvider] — the SAME list `/profile/routines` renders
/// (coach-assigned + self-created, archived excluded by both queries).
///
/// It used to read only `assignedRoutinesProvider`, so an athlete without a
/// PF and with their own routine saw "0 activas" on the tile and the routine
/// with the ACTIVA chip one tap later. Sharing the source keeps the two
/// surfaces from drifting again.
///
/// Returns 0 during loading/error so the CUENTA tile subtitle "N activas"
/// renders without flicker. Mirrors the [pendingRequestCountProvider] pattern
/// from feed-friend-requests-inbox (ADR-FRI-007).
///
/// REQ-PSR-020 — Mis rutinas tile subtitle in ProfileCuentaSection.
final activeRoutinesCountProvider =
    Provider.autoDispose.family<int, String>((ref, uid) {
  final asyncValue = ref.watch(unifiedRoutinesProvider(uid));
  return asyncValue.maybeWhen(
    data: (list) => list.length,
    orElse: () => 0,
  );
});
