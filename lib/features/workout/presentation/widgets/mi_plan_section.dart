import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../coach/application/trainer_link_providers.dart';
import '../../../coach/domain/trainer_link.dart';
import '../../../coach/domain/trainer_link_status.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../profile/application/user_public_profile_providers.dart';
import '../../application/assigned_routine_providers.dart';
import '../../application/session_providers.dart' show currentUidProvider;
import '../../domain/routine.dart';

/// Displays the list of trainer-assigned routines for the current athlete.
/// Replaces the private `_TuRutinaSection` placeholder in WorkoutScreen.
///
/// REQ-COACH-PLANS-012..018, SCENARIO-444..451.
class MiPlanSection extends ConsumerWidget {
  const MiPlanSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUidProvider) ?? '';
    if (uid.isEmpty) return const SizedBox.shrink();

    final plansAsync = ref.watch(assignedRoutinesProvider(uid));
    final linkAsync = ref.watch(currentAthleteLinkProvider);

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppL10n.of(context).coachMiPlanTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        plansAsync.when(
          loading: () => const _SectionLoadingState(),
          error: (err, _) => _SectionErrorState(
            errorMessage: err.toString(),
            onRetry: () => ref.invalidate(assignedRoutinesProvider(uid)),
          ),
          data: (plans) {
            if (plans.isEmpty) {
              return const _SectionEmptyState();
            }
            // Solo marcamos el más reciente como "Actual" cuando hay más
            // de un plan asignado — con uno solo el badge es redundante.
            // `listAssignedTo` ordena por createdAt DESC, así que el más
            // nuevo es plans[0].
            final showCurrentBadge = plans.length > 1;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < plans.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PlanCard(
                      plan: plans[i],
                      linkAsync: linkAsync,
                      isCurrent: showCurrentBadge && i == 0,
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

// ── Loading state ─────────────────────────────────────────────────────────────

class _SectionLoadingState extends StatelessWidget {
  const _SectionLoadingState();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _SectionErrorState extends StatelessWidget {
  const _SectionErrorState({required this.onRetry, this.errorMessage});
  final VoidCallback onRetry;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.coachMiPlanError,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: palette.textMuted,
            ),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: onRetry,
            child: Text(
              'Reintentar',
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
  const _SectionEmptyState();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        l10n.coachMiPlanEmpty,
        style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted),
      ),
    );
  }
}

// ── Plan Card ─────────────────────────────────────────────────────────────────

bool _isLinkTerminated(AsyncValue<TrainerLink?> linkAsync, Routine routine) {
  final link = linkAsync.valueOrNull;
  if (link == null) return false;
  return link.status == TrainerLinkStatus.terminated &&
      link.trainerId == routine.assignedBy;
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard({
    required this.plan,
    required this.linkAsync,
    this.isCurrent = false,
  });

  final Routine plan;
  final AsyncValue<TrainerLink?> linkAsync;

  /// Marca este card como el plan activo del atleta. Solo se setea desde
  /// `MiPlanSection` cuando hay más de un plan asignado y este es el más
  /// reciente (plans[0], ordenado por createdAt DESC).
  final bool isCurrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final trainerAsync = plan.assignedBy != null
        ? ref.watch(userPublicProfileProvider(plan.assignedBy!))
        : const AsyncData(null);

    final trainerName = trainerAsync.maybeWhen(
      data: (profile) => profile?.displayName,
      orElse: () => null,
    );

    final isTerminated = _isLinkTerminated(linkAsync, plan);

    return InkWell(
      key: const Key('mi_plan_card'),
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/workout/routine/${plan.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(16),
          // Outline más marcado en el actual para que destaque sin gritar.
          border: Border.all(
            color: isCurrent ? palette.accent : palette.border,
            width: isCurrent ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    plan.name,
                    style: GoogleFonts.barlow(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                if (isCurrent) ...[
                  const SizedBox(width: 8),
                  const _ActualChip(),
                ],
              ],
            ),
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
            if (isTerminated) ...[
              const SizedBox(height: 8),
              _FinalizadoChip(),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Actual chip ───────────────────────────────────────────────────────────────

class _ActualChip extends StatelessWidget {
  const _ActualChip();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      key: const Key('mi_plan_current_chip'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: palette.accent.withValues(alpha: 0.5)),
      ),
      child: Text(
        AppL10n.of(context).coachMiPlanCurrent.toUpperCase(),
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
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: palette.highlight.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(9999),
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
