import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/motion/treino_fade_slide_in.dart';
import '../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../core/widgets/motion/treino_tappable.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../workout/application/unified_routines_providers.dart';
import '../../workout/presentation/widgets/routine_card.dart';
import '../application/user_providers.dart' show userProfileProvider;

/// Read-only mirror of the unified RUTINAS list (workout-area redesign
/// slice 1, 2026-07-27): ONE list with the trainer-assigned plans pinned on
/// top — each with a "DE TU COACH" chip — followed by the athlete's
/// self-created routines. The card matching `UserProfile.activeRoutineId`
/// carries the "ACTIVA" chip, always (lazy adoption keeps the marker set).
///
/// PRE-slice-1 this screen rendered 2 stacked sections (assigned / own) with
/// its own chip-gating rules; those now live unified in the Workout tab's
/// `RutinasSection` and this mirror follows the same contract.
///
/// Decisions preserved from 2026-06-19/30:
///   - **Find-a-PF promo**: when the athlete has NO trainer-assigned plan,
///     the "Buscar PF" card renders below the list (was the assigned-section
///     empty state) — discovery stays promoted.
///   - **Read-only**: no edit/archive/toggle-active actions here — those
///     live in the Workout tab. Cards are tap-to-open.
class ProfileRoutinesScreen extends ConsumerWidget {
  const ProfileRoutinesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final myUid = ref.watch(currentUidProvider) ?? '';

    final entriesAsync = ref.watch(unifiedRoutinesProvider(myUid));
    final activeId = ref.watch(
      userProfileProvider.select((a) => a.valueOrNull?.activeRoutineId),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: TreinoTappable(
            onTap: () => context.pop(),
            child: Row(
              children: [
                Icon(TreinoIcon.back, size: 20, color: palette.textPrimary),
                const SizedBox(width: 14),
                Text(
                  'MIS RUTINAS', // i18n: Fase 6 Etapa 3
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Body ─────────────────────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              4,
              20,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            child: TreinoStateSwitcher(
              childKey: ValueKey(entriesAsync.when(
                skipLoadingOnReload: true,
                loading: () => 'loading',
                error: (_, __) => 'error',
                data: (entries) => entries.isEmpty ? 'empty' : 'data',
              )),
              child: entriesAsync.when(
                skipLoadingOnReload: true,
                loading: () => _LoadingBlock(palette: palette),
                error: (_, __) => _ErrorBlock(
                  message: 'No pudimos cargar tus rutinas. Intentá de nuevo.',
                  palette: palette,
                ),
                data: (entries) {
                  final hasCoachPlan = entries.any((e) => e.fromCoach);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (entries.isEmpty)
                        _OwnEmptyState(palette: palette, l10n: l10n)
                      else
                        for (var i = 0; i < entries.length; i++) ...[
                          if (i > 0) const SizedBox(height: 12),
                          // key por routine.id: sin ella, Flutter matchea los
                          // TreinoFadeSlideIn por posición y una recomputación
                          // en vivo (ej. el coach asigna un plan que se pinea
                          // arriba) hace que las filas existentes reusen el
                          // State one-shot de OTRO ítem — parpadea la fila
                          // equivocada en vez de la realmente nueva.
                          TreinoFadeSlideIn(
                            key: ValueKey(entries[i].routine.id),
                            delay: AppMotion.stagger(i),
                            child: _RoutineRow(
                              entry: entries[i],
                              isActive: entries[i].routine.id == activeId,
                            ),
                          ),
                        ],
                      if (!hasCoachPlan) ...[
                        const SizedBox(height: 28),
                        // Continúa la cascada como último elemento: sin esto
                        // el promo aparecía instantáneo en el frame 0 pese a
                        // estar debajo de las rows que sí staggerean,
                        // invirtiendo la jerarquía top-down que comunica el
                        // stagger.
                        TreinoFadeSlideIn(
                          delay: AppMotion.stagger(entries.length),
                          child:
                              _FindTrainerPromo(palette: palette, l10n: l10n),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Find-a-PF promo (shown while no trainer-assigned plan exists) ───────────

class _FindTrainerPromo extends StatelessWidget {
  const _FindTrainerPromo({required this.palette, required this.l10n});
  final AppPalette palette;
  final AppL10n l10n;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('profile_routines_assigned_empty'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.profileRoutinesNoTrainerBody,
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w400,
              fontSize: 14,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const Key('profile_routines_find_trainer_cta'),
            onPressed: () => context.push('/coach'),
            icon: Icon(TreinoIcon.search, size: 16, color: palette.accent),
            label: Text(
              l10n.profileRoutinesNoTrainerCta,
              style: TextStyle(color: palette.accent),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: palette.accent.withValues(alpha: 0.6)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state (no routines at all) ────────────────────────────────────────

class _OwnEmptyState extends StatelessWidget {
  const _OwnEmptyState({required this.palette, required this.l10n});
  final AppPalette palette;
  final AppL10n l10n;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('profile_routines_own_empty'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        l10n.profileRoutinesNoOwnBody,
        textAlign: TextAlign.center,
        style: GoogleFonts.barlow(
          fontWeight: FontWeight.w400,
          fontSize: 14,
          color: palette.textMuted,
        ),
      ),
    );
  }
}

// ── Routine row (RoutineCard + corner chips) ────────────────────────────────

class _RoutineRow extends StatelessWidget {
  const _RoutineRow({required this.entry, required this.isActive});
  final UnifiedRoutineEntry entry;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final showChips = isActive || entry.fromCoach;
    if (!showChips) return RoutineCard(routine: entry.routine);
    // When chipped, stack the chips in the corner without rewriting the card.
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    // RoutineCard wraps a Container with no explicit width — sin el
    // SizedBox de adentro colapsa a su intrinsic size cuando se mete en un
    // Stack (Stack no estira children por default; los Positioned tampoco
    // estiran al child non-positioned). Forzar full-width acá iguala el
    // ancho visual con las cards sin chip.
    return Stack(
      children: [
        SizedBox(
          width: double.infinity,
          child: RoutineCard(routine: entry.routine),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (entry.fromCoach)
                _Chip(
                  key: Key('profile_routines_coach_chip_${entry.routine.id}'),
                  label: l10n.workoutRutinasCoachChip,
                  color: palette.highlight,
                ),
              if (entry.fromCoach && isActive) const SizedBox(width: 6),
              if (isActive)
                _Chip(
                  key: const Key('profile_routines_active_chip'),
                  label: l10n.profileRoutinesActiveChip,
                  color: palette.accent,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 1.2,
          color: color,
        ),
      ),
    );
  }
}

// ── Shared loading / error blocks ───────────────────────────────────────────

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.message, required this.palette});
  final String message;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: GoogleFonts.barlow(
          fontWeight: FontWeight.w400,
          fontSize: 14,
          color: palette.textMuted,
        ),
      ),
    );
  }
}
