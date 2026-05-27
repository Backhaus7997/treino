import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workout/application/assigned_routine_providers.dart'
    show assignedRoutinesProvider;
import '../../workout/domain/routine.dart';

export '../../workout/application/assigned_routine_providers.dart'
    show assignedRoutinesProvider;

/// Synchronous count derived from [assignedRoutinesProvider].
///
/// Returns 0 during loading/error so the CUENTA tile subtitle "N activas"
/// renders without flicker. Mirrors the [pendingRequestCountProvider] pattern
/// from feed-friend-requests-inbox (ADR-FRI-007).
///
/// REQ-PSR-020 — Mis rutinas tile subtitle in ProfileCuentaSection.
/// // i18n: Fase 6 Etapa 3
final assignedRoutinesCountProvider =
    Provider.autoDispose.family<int, String>((ref, uid) {
  final asyncValue = ref.watch(assignedRoutinesProvider(uid));
  return asyncValue.maybeWhen(
    data: (list) => list.length,
    orElse: () => 0,
  );
});
