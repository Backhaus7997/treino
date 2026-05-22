import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../chat/application/chat_providers.dart';
import '../../profile/application/user_public_profile_providers.dart';
import '../../workout/application/assigned_routine_providers.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../workout/domain/routine.dart';
import 'coach_strings.dart';

/// Trainer's drill-down view for a specific athlete.
///
/// Shows the athlete header (avatar + displayName) and all plans assigned by
/// the current trainer to this athlete. Provides a "CREAR PLAN" CTA that
/// navigates to the RoutineEditorScreen.
///
/// Lives under ShellRoute — NO own Scaffold (bottom bar provided by shell).
/// REQ-COACH-PLANS-020, 021, 022 · SCENARIO-454, 455, 456.
class AthleteDetailScreen extends ConsumerWidget {
  const AthleteDetailScreen({super.key, required this.athleteId});

  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final trainerUid = ref.watch(currentUidProvider) ?? '';

    final profileAsync = ref.watch(userPublicProfileProvider(athleteId));
    final plansAsync = ref.watch(assignedRoutinesProvider(athleteId));

    return Column(
      children: [
        // ── Header bar ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
          child: Row(
            children: [
              IconButton(
                icon: Icon(TreinoIcon.back, color: palette.textPrimary),
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/coach'),
              ),
              const SizedBox(width: 4),
              profileAsync.maybeWhen(
                data: (profile) => Text(
                  profile?.displayName ?? '...',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: palette.textPrimary,
                  ),
                ),
                orElse: () => Text(
                  '...',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Body ─────────────────────────────────────────────────────────
        Expanded(
          child: _AthleteDetailBody(
            athleteId: athleteId,
            trainerUid: trainerUid,
            profileAsync: profileAsync,
            plansAsync: plansAsync,
          ),
        ),
      ],
    );
  }
}

class _AthleteDetailBody extends ConsumerWidget {
  const _AthleteDetailBody({
    required this.athleteId,
    required this.trainerUid,
    required this.profileAsync,
    required this.plansAsync,
  });

  final String athleteId;
  final String trainerUid;
  final AsyncValue<dynamic> profileAsync;
  final AsyncValue<List<Routine>> plansAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);

    if (profileAsync.isLoading || plansAsync.isLoading) {
      return Center(
        child: CircularProgressIndicator(color: palette.accent),
      );
    }

    if (profileAsync.hasError) {
      return Center(
        child: Text(
          'No pudimos cargar este perfil.',
          style: GoogleFonts.barlow(color: palette.textMuted, fontSize: 14),
        ),
      );
    }

    if (plansAsync.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Error cargando planes:',
                style:
                    GoogleFonts.barlow(color: palette.textMuted, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                plansAsync.error.toString(),
                style:
                    GoogleFonts.barlow(color: palette.textMuted, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Client-side filter: only show plans assigned by current trainer
    final allPlans = plansAsync.valueOrNull ?? const [];
    final myPlans = allPlans.where((r) => r.assignedBy == trainerUid).toList();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            children: [
              // ── Athlete header ──────────────────────────────────────
              _AthleteHeader(profileAsync: profileAsync),
              const SizedBox(height: 20),

              // ── Planes section ──────────────────────────────────────
              Text(
                'PLANES ASIGNADOS',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              if (myPlans.isEmpty)
                Text(
                  CoachStrings.athleteDetailNoPlans,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 14,
                    color: palette.textMuted,
                  ),
                )
              else
                for (final plan in myPlans) ...[
                  _PlanCard(
                    plan: plan,
                    onTap: () => context.push('/workout/routine/${plan.id}'),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),

        // ── MENSAJE + CREAR PLAN buttons ──────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _onMessage(context, ref),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: palette.accent, width: 1),
                    foregroundColor: palette.accent,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                  icon: Icon(TreinoIcon.chat, size: 18, color: palette.accent),
                  label: Text(
                    'MENSAJE',
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      context.push('/workout/routine-editor/$athleteId'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: palette.bg,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                  child: Text(
                    CoachStrings.createPlanCta,
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _onMessage(BuildContext context, WidgetRef ref) async {
    if (trainerUid.isEmpty) return;
    try {
      final chat = await ref.read(chatRepositoryProvider).getOrCreate(
            selfId: trainerUid,
            otherId: athleteId,
          );
      if (!context.mounted) return;
      context.push('/coach/chat/${chat.chatId}?other=$athleteId');
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pudimos abrir el chat. Probá de nuevo.'),
        ),
      );
    }
  }
}

// ── Athlete header ─────────────────────────────────────────────────────────────

class _AthleteHeader extends StatelessWidget {
  const _AthleteHeader({required this.profileAsync});
  final AsyncValue<dynamic> profileAsync;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final profile = profileAsync.valueOrNull;
    final name = (profile != null) ? (profile.displayName ?? '...') : '...';

    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.bg,
            border: Border.all(color: palette.border, width: 1),
          ),
          alignment: Alignment.center,
          child:
              Icon(TreinoIcon.tabProfile, size: 28, color: palette.textMuted),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            name,
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color: palette.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Plan card ─────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, this.onTap});
  final Routine plan;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(12),
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
            const SizedBox(height: 4),
            Text(
              '${plan.days.length} ${plan.days.length == 1 ? "día" : "días"} · ${plan.split}',
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: 12,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
