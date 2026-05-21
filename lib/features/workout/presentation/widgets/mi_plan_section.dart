import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../coach/application/trainer_link_providers.dart';
import '../../../coach/domain/trainer_link.dart';
import '../../../coach/domain/trainer_link_status.dart';
import '../../../coach/presentation/coach_strings.dart';
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
          CoachStrings.miPlanTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        plansAsync.when(
          loading: () => const _SectionLoadingState(),
          error: (_, __) => _SectionErrorState(
            onRetry: () => ref.invalidate(assignedRoutinesProvider(uid)),
          ),
          data: (plans) {
            if (plans.isEmpty) {
              return const _SectionEmptyState();
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: plans
                  .map((plan) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _PlanCard(plan: plan, linkAsync: linkAsync),
                      ))
                  .toList(),
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
  const _SectionErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            CoachStrings.miPlanError,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: palette.textMuted,
            ),
          ),
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        CoachStrings.miPlanEmpty,
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
  const _PlanCard({required this.plan, required this.linkAsync});

  final Routine plan;
  final AsyncValue<TrainerLink?> linkAsync;

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
          border: Border.all(color: palette.border, width: 1),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plan.name,
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: palette.textPrimary,
              ),
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
        CoachStrings.miPlanFinalizado,
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
