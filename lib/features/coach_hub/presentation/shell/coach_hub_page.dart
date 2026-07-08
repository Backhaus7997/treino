import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Wraps a Coach Hub section [child] in a [NoTransitionPage] so switching
/// between sidebar destinations swaps the content area INSTANTLY, with no
/// cross-fade.
///
/// Why this exists (bug W-COACH-NAV-01):
/// The section routes originally used `GoRoute.builder`, which makes go_router
/// synthesize a default platform [Page] with a fade transition. During that
/// fade the outgoing and incoming section widgets are BOTH mounted for a few
/// hundred ms, so their content visibly overlaps inside the shell's content
/// area (e.g. Biblioteca's exercise cards bleeding through the Pagos screen).
///
/// The shell wrapper itself already uses [NoTransitionPage]; the section pages
/// nested under it must do the same, otherwise the child transition still
/// runs. Using this helper in every section's `pageBuilder` keeps the swap
/// instant and the two screens from co-existing on screen.
///
/// Deliberately scoped to the Coach Hub (web) router — the mobile app relies
/// on its own `_noAnim` helper and platform transitions elsewhere, so we do
/// NOT touch the shared `AppTheme.pageTransitionsTheme`.
Page<void> coachHubPage(Widget child, {LocalKey? key}) {
  return NoTransitionPage<void>(key: key, child: child);
}
