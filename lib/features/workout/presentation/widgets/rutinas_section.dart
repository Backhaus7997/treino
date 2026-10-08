import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../coach/application/trainer_link_providers.dart';
import '../../../coach/domain/trainer_link.dart';
import '../../../coach/domain/trainer_link_status.dart';
import '../../../profile/application/user_providers.dart';
import '../../../profile/application/user_public_profile_providers.dart';
import '../../application/assigned_routine_providers.dart';
import '../../application/routine_providers.dart'
    show invalidateRoutineById, routineRepositoryProvider;
import '../../application/session_providers.dart' show currentUidProvider;
import '../../application/unified_routines_providers.dart';
import '../../application/user_routines_providers.dart';
import '../../domain/routine.dart';
import 'coach_chip.dart';
import 'routine_meta.dart';

const int _kRoutineCap = 10;

/// Unified RUTINAS list for the workout tab — workout-area redesign slice 1
/// (2026-07-27). Merges the former `MiPlanSection` (trainer-assigned plans)
/// and `MisRutinasSection` (self-created routines) into ONE list:
///
///   * Coach-assigned routines are PINNED on top with a "DE TU COACH" chip
///     (same visual language as the ACTIVA chip, highlight color).
///   * The ACTIVA chip renders on whichever card matches
///     `UserProfile.activeRoutineId` — always, even with a single routine
///     (lazy adoption in [unifiedRoutinesProvider] keeps the marker set).
///   * "Marcar como activa" is available on every NON-active card once the
///     unified list has 2+ routines — coach plans included. There is no
///     unmark action: with lazy adoption there is always exactly one active
///     routine while the list is non-empty, so switching is the only verb.
///   * Edit/archive stay exclusive to self-created routines.
///
/// The create CTA + the 10-routine cap only look at SELF-CREATED routines —
/// coach plans never count against the athlete's cap.
class RutinasSection extends ConsumerWidget {
  const RutinasSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUidProvider) ?? '';
    if (uid.isEmpty) return const SizedBox.shrink();

    final entriesAsync = ref.watch(unifiedRoutinesProvider(uid));
    final theme = Theme.of(context);
    final l10n = AppL10n.of(context);
    final useStackedHeader = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final Widget? headerAction = entriesAsync.maybeWhen(
      skipLoadingOnReload: true,
      data: (entries) {
        final ownCount = entries.where((e) => !e.fromCoach).length;
        if (ownCount >= _kRoutineCap) return null;
        return _CtaButton(
          onPressed: () => context.push('/workout/my-routine-editor'),
        );
      },
      orElse: () => null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header row ────────────────────────────────────────────────────────
        if (useStackedHeader)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.workoutMisRutinasSectionTitle,
                style: theme.textTheme.titleMedium,
              ),
              if (headerAction != null) ...[
                const SizedBox(height: 12),
                headerAction,
              ],
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.workoutMisRutinasSectionTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (headerAction != null) headerAction,
            ],
          ),
        const SizedBox(height: 12),
        // ── Cap-reached inline message ───────────────────────────────────────
        // Renders only when there are 10 active SELF-CREATED routines.
        entriesAsync.maybeWhen(
          skipLoadingOnReload: true,
          data: (entries) {
            final ownCount = entries.where((e) => !e.fromCoach).length;
            if (ownCount < _kRoutineCap) return const SizedBox.shrink();
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
        entriesAsync.when(
          // Keep the previous list on screen while the underlying streams
          // recompose (archive/create/assignment) — no spinner flicker.
          skipLoadingOnReload: true,
          loading: () => const _SectionLoadingState(),
          error: (err, _) => _SectionErrorState(
            onRetry: () {
              ref
                ..invalidate(assignedRoutinesProvider(uid))
                ..invalidate(userCreatedRoutinesProvider(uid))
                ..invalidate(unifiedRoutinesProvider(uid));
            },
          ),
          data: (entries) {
            if (entries.isEmpty) {
              return _SectionEmptyState(
                onCta: () => context.push('/workout/my-routine-editor'),
              );
            }
            // `activeRoutineId` viene del UserProfile; durante el loading de
            // profile (cold start) ningún card se marca como activa — estado
            // transitorio aceptable hasta que la adopción perezosa resuelva.
            final activeId = ref.watch(
              userProfileProvider.select(
                (a) => a.valueOrNull?.activeRoutineId,
              ),
            );
            final linkAsync = ref.watch(currentAthleteLinkProvider);
            // El toggle solo aporta cuando hay algo que elegir — con una
            // sola rutina la adopción perezosa ya la dejó activa.
            final canToggleActive = entries.length > 1;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _RoutineCard(
                      routine: entry.routine,
                      fromCoach: entry.fromCoach,
                      isActive: entry.routine.id == activeId,
                      canToggleActive: canToggleActive,
                      linkAsync: linkAsync,
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
  const _CtaButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
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
          borderRadius: BorderRadius.circular(AppRadius.sm),
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

// ── Routine card (both kinds) ─────────────────────────────────────────────────

bool _isLinkTerminated(AsyncValue<TrainerLink?> linkAsync, Routine routine) {
  final link = linkAsync.valueOrNull;
  if (link == null) return false;
  return link.status == TrainerLinkStatus.terminated &&
      link.trainerId == routine.assignedBy;
}

class _RoutineCard extends ConsumerWidget {
  const _RoutineCard({
    required this.routine,
    required this.fromCoach,
    required this.isActive,
    required this.canToggleActive,
    required this.linkAsync,
  });

  final Routine routine;

  /// Trainer-assigned routine — pinned on top by [unifiedRoutinesProvider],
  /// renders the "DE TU COACH" chip + trainer name, and hides edit/archive.
  final bool fromCoach;

  /// This card matches `UserProfile.activeRoutineId`.
  final bool isActive;

  /// Whether "Marcar como activa" is offered on non-active cards — true when
  /// the unified list has 2+ routines (coach plans included).
  final bool canToggleActive;

  /// Current athlete↔trainer link, used for the "Plan finalizado" chip on
  /// coach cards whose link was terminated.
  final AsyncValue<TrainerLink?> linkAsync;

  Future<void> _markActive(BuildContext context, WidgetRef ref) async {
    final uid = ref.read(currentUidProvider) ?? '';
    if (uid.isEmpty) return;
    final l10n = AppL10n.of(context);
    try {
      await ref.read(userRepositoryProvider).update(uid, {
        'activeRoutineId': routine.id,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.workoutMisRutinasMarkActiveSuccess)),
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

  Future<void> _confirmArchive(BuildContext context, WidgetRef ref) async {
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

    // Captured before the async gap so the cache drop survives an unmount.
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await ref.read(routineRepositoryProvider).archive(routine.id);
      // Archivar sólo cambia `status` en el doc. Los lectores one-shot
      // cachean el doc entero, así que sin esto la rutina archivada sigue
      // siendo arrancable hasta que se reinicie la app.
      invalidateRoutineById(container, routine.id);
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

    // Trainer display name — coach cards only (mirrors the old _PlanCard).
    final trainerAsync = fromCoach && routine.assignedBy != null
        ? ref.watch(userPublicProfileProvider(routine.assignedBy!))
        : const AsyncData(null);
    final trainerName = trainerAsync.maybeWhen(
      data: (profile) => profile?.displayName,
      orElse: () => null,
    );

    final isTerminated = fromCoach && _isLinkTerminated(linkAsync, routine);
    final showToggle = canToggleActive && !isActive;
    // Coach cards only carry the toggle; hide the whole menu when empty.
    final showMenu = !fromCoach || showToggle;
    final useStackedTitle = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final title = Text(
      routine.name,
      style: GoogleFonts.barlow(
        fontWeight: FontWeight.w600,
        fontSize: 14,
        color: palette.textPrimary,
      ),
    );
    final statusChips = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (fromCoach) CoachChip(routineId: routine.id),
        if (isActive) _ActivaChip(routineId: routine.id),
      ],
    );

    return InkWell(
      key: Key('routine_card_${routine.id}'),
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: () => context.push('/workout/routine/${routine.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(AppRadius.md),
          // Outline más marcado en la activa para que destaque sin gritar.
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
                  if (useStackedTitle) ...[
                    title,
                    if (fromCoach || isActive) ...[
                      const SizedBox(height: 8),
                      statusChips,
                    ],
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: title),
                        if (fromCoach || isActive) ...[
                          const SizedBox(width: 8),
                          statusChips,
                        ],
                      ],
                    ),
                  if (fromCoach) ...[
                    // Mirrors the old _PlanCard: the trainer-name line only
                    // renders once the public profile resolves.
                    if (trainerName != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        trainerName,
                        style: GoogleFonts.barlow(
                          fontWeight: FontWeight.w400,
                          fontSize: 12,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ] else ...[
                    const SizedBox(height: 4),
                    Text(
                      // #648: la jerga deja de liderar. Antes esta línea era
                      // '{SPLIT} · {NIVEL}' y el split iba primero y en
                      // mayúsculas. Ahora comparte fuente con la tarjeta de
                      // EXPLORAR, que es lo que impide que vuelvan a divergir.
                      routineMetaSegments(routine, l10n)
                          .map((s) => s.toUpperCase())
                          .join(' · '),
                      style: GoogleFonts.barlow(
                        fontWeight: FontWeight.w400,
                        fontSize: 12,
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                  if (isTerminated) ...[
                    const SizedBox(height: 8),
                    const _FinalizadoChip(),
                  ],
                ],
              ),
            ),
            // Overflow menu
            if (showMenu)
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
                    case _CardAction.markActive:
                      _markActive(context, ref);
                  }
                },
                itemBuilder: (_) => [
                  if (showToggle)
                    PopupMenuItem(
                      key: Key('routine_card_toggle_active_${routine.id}'),
                      value: _CardAction.markActive,
                      child: Text(l10n.workoutMisRutinasOverflowMarkActive),
                    ),
                  if (!fromCoach) ...[
                    PopupMenuItem(
                      value: _CardAction.edit,
                      child: Text(l10n.workoutMisRutinasOverflowEdit),
                    ),
                    PopupMenuItem(
                      value: _CardAction.archive,
                      child: Text(l10n.workoutMisRutinasOverflowArchive),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

enum _CardAction { edit, archive, markActive }

// ── ACTIVA chip ───────────────────────────────────────────────────────────────

class _ActivaChip extends StatelessWidget {
  const _ActivaChip({required this.routineId});

  final String routineId;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      key: Key('routine_active_chip_$routineId'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.full),
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

// ── Finalizado chip ───────────────────────────────────────────────────────────

class _FinalizadoChip extends StatelessWidget {
  const _FinalizadoChip();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: palette.highlight.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: palette.highlight.withValues(alpha: 0.4)),
      ),
      child: Text(
        AppL10n.of(context).coachMiPlanFinalizado,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w600,
          fontSize: 11,
          letterSpacing: 1.2,
          color: palette.highlight,
        ),
      ),
    );
  }
}
