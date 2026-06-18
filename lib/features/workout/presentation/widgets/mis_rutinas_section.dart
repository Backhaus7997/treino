import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../features/profile/application/user_providers.dart';
import '../../../../features/profile/domain/experience_level.dart'
    show ExperienceLevelEs;
import '../../../../l10n/app_l10n.dart';
import '../../application/routine_providers.dart'
    show routineRepositoryProvider;
import '../../application/session_providers.dart' show currentUidProvider;
import '../../application/user_routines_providers.dart';
import '../../domain/routine.dart';

const int _kRoutineCap = 10;

/// Displays the authenticated athlete's self-created routines.
/// Inserted between [MiPlanSection] and [PlantillasSection] in _AthleteWorkout.
///
/// States: loading → spinner; error → message + retry; empty → motivational
/// copy + enabled CTA; loaded → list of [_UserRoutineCard] + CTA; cap (10)
/// → list + disabled CTA with tooltip.
///
/// REQ-USR-001..006, SCENARIO-USR-001..008, ADR-USR-02, ADR-USR-04.
class MisRutinasSection extends ConsumerWidget {
  const MisRutinasSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUidProvider) ?? '';
    if (uid.isEmpty) return const SizedBox.shrink();

    final routinesAsync = ref.watch(userCreatedRoutinesProvider(uid));
    final theme = Theme.of(context);
    final l10n = AppL10n.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header row ────────────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.workoutMisRutinasSectionTitle,
                style: theme.textTheme.titleMedium,
              ),
            ),
            routinesAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (routines) {
                final capReached = routines.length >= _kRoutineCap;
                // When cap-reached, the header CTA is hidden and the cap
                // message is rendered inline below the header (single source
                // of feedback — no duplicate sticky bottom CTA).
                if (capReached) return const SizedBox.shrink();
                return _CtaButton(
                  capReached: false,
                  onPressed: () => context.push('/workout/my-routine-editor'),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        // ── Cap-reached inline message ───────────────────────────────────────
        // Replaces the bottom sticky CTA that previously hosted this copy.
        // Renders only when there are 10 active user-created routines.
        routinesAsync.maybeWhen(
          data: (routines) {
            if (routines.length < _kRoutineCap) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Llegaste al máximo de $_kRoutineCap rutinas activas. '
                'Archivá una para crear otra.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppPalette.of(context).textMuted,
                ),
              ),
            );
          },
          orElse: () => const SizedBox.shrink(),
        ),
        // ── Content ───────────────────────────────────────────────────────────
        routinesAsync.when(
          loading: () => const _SectionLoadingState(),
          error: (err, _) => _SectionErrorState(
            onRetry: () => ref.invalidate(userCreatedRoutinesProvider(uid)),
          ),
          data: (routines) {
            if (routines.isEmpty) {
              return _SectionEmptyState(
                onCta: () => context.push('/workout/my-routine-editor'),
              );
            }
            // `activeRoutineId` viene del UserProfile; durante el loading
            // de profile (cold start) ningún card se marca como activa —
            // estado transitorio aceptable, no flickea de "ACTIVA" a vacío.
            final activeId =
                ref.watch(userProfileProvider).valueOrNull?.activeRoutineId;
            // El chip "ACTIVA" solo aporta info cuando hay 2+ rutinas —
            // con una sola la activación implícita ya está clara.
            final showActiveBadge = routines.length > 1;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final routine in routines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _UserRoutineCard(
                      routine: routine,
                      isActive: showActiveBadge && routine.id == activeId,
                      canToggleActive: showActiveBadge,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ── CTA button ────────────────────────────────────────────────────────────────

class _CtaButton extends StatelessWidget {
  const _CtaButton({
    required this.capReached,
    required this.onPressed,
  });

  final bool capReached;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    if (capReached) {
      // Parent (Row/Column) decides how to size this — we don't wrap in
      // Flexible/Expanded here because that conflicts with vertical parents.
      return Tooltip(
        message: AppL10n.of(context).workoutMisRutinasCtaDisabledTooltip,
        child: Text(
          // Inline cap hint (REQ-USR-005)
          'Llegaste al máximo de $_kRoutineCap rutinas activas. Archivá una para crear otra.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
          softWrap: true,
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(TreinoIcon.plus, size: 16, color: palette.accent),
      label: Text(
        AppL10n.of(context).workoutMisRutinasCta,
        style: TextStyle(color: palette.accent),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: palette.accent.withValues(alpha: 0.6)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

// ── Loading state ─────────────────────────────────────────────────────────────

class _SectionLoadingState extends StatelessWidget {
  const _SectionLoadingState();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _SectionErrorState extends StatelessWidget {
  const _SectionErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppL10n.of(context).workoutMisRutinasError,
            style:
                theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onRetry,
            child: Text(
              AppL10n.of(context).workoutMisRutinasErrorRetry,
              style: TextStyle(color: palette.accent),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _SectionEmptyState extends StatelessWidget {
  const _SectionEmptyState({required this.onCta});

  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        AppL10n.of(context).workoutMisRutinasEmptyState,
        style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted),
      ),
    );
  }
}

// ── User Routine Card ─────────────────────────────────────────────────────────

class _UserRoutineCard extends ConsumerWidget {
  const _UserRoutineCard({
    required this.routine,
    this.isActive = false,
    this.canToggleActive = false,
  });

  final Routine routine;

  /// Marca este card como la rutina activa del atleta. Solo se setea desde
  /// `MisRutinasSection` cuando hay 2+ rutinas user-created y el id de ésta
  /// coincide con `UserProfile.activeRoutineId`.
  final bool isActive;

  /// Habilita las acciones "Marcar/Desmarcar como activa" en el overflow.
  /// Solo `true` cuando hay 2+ rutinas — con una sola el toggle no aplica.
  final bool canToggleActive;

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final uid = ref.read(currentUidProvider) ?? '';
    if (uid.isEmpty) return;
    final l10n = AppL10n.of(context);
    final wasActive = isActive;
    try {
      await ref.read(userRepositoryProvider).update(uid, {
        'activeRoutineId': wasActive ? null : routine.id,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              wasActive
                  ? l10n.workoutMisRutinasUnmarkActiveSuccess
                  : l10n.workoutMisRutinasMarkActiveSuccess,
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.workoutMisRutinasActiveError)),
        );
      }
    }
  }

  Future<void> _confirmArchive(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l10n = AppL10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.workoutMisRutinasConfirmTitle),
        content: Text(l10n.workoutMisRutinasConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.workoutMisRutinasConfirmCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.workoutMisRutinasConfirmConfirm),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    try {
      await ref.read(routineRepositoryProvider).archive(routine.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.workoutMisRutinasArchiveSuccess)),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.workoutMisRutinasArchiveError)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return InkWell(
      key: Key('user_routine_card_${routine.id}'),
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/workout/routine/${routine.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? palette.accent : palette.border,
            width: isActive ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          routine.name,
                          style: GoogleFonts.barlow(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      if (isActive) ...[
                        const SizedBox(width: 8),
                        const _ActivaChip(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(routine.split ?? l10n.workoutSplitFallback).toUpperCase()} · ${routine.level.displayNameEs.toUpperCase()}',
                    style: GoogleFonts.barlow(
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            // Overflow menu
            PopupMenuButton<_CardAction>(
              key: Key('routine_card_more_${routine.id}'),
              tooltip: l10n.workoutRoutineOptionsA11y,
              icon: Icon(TreinoIcon.dotsThree, color: palette.textMuted),
              onSelected: (action) {
                switch (action) {
                  case _CardAction.edit:
                    context.push(
                      '/workout/my-routine-editor',
                      extra: routine.id,
                    );
                  case _CardAction.archive:
                    _confirmArchive(context, ref);
                  case _CardAction.toggleActive:
                    _toggleActive(context, ref);
                }
              },
              itemBuilder: (_) => [
                if (canToggleActive)
                  PopupMenuItem(
                    key: Key('routine_card_toggle_active_${routine.id}'),
                    value: _CardAction.toggleActive,
                    child: Text(
                      isActive
                          ? l10n.workoutMisRutinasOverflowUnmarkActive
                          : l10n.workoutMisRutinasOverflowMarkActive,
                    ),
                  ),
                PopupMenuItem(
                  value: _CardAction.edit,
                  child: Text(l10n.workoutMisRutinasOverflowEdit),
                ),
                PopupMenuItem(
                  value: _CardAction.archive,
                  child: Text(l10n.workoutMisRutinasOverflowArchive),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _CardAction { edit, archive, toggleActive }

// ── ACTIVA chip ───────────────────────────────────────────────────────────────

class _ActivaChip extends StatelessWidget {
  const _ActivaChip();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      key: const Key('user_routine_active_chip'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: palette.accent.withValues(alpha: 0.5)),
      ),
      child: Text(
        AppL10n.of(context).workoutMisRutinasActiveChip,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 1.2,
          color: palette.accent,
        ),
      ),
    );
  }
}
