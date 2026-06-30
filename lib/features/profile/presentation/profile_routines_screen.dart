import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../auth/application/auth_providers.dart';
import '../../workout/application/assigned_routine_providers.dart';
import '../../workout/application/user_routines_providers.dart';
import '../../workout/domain/routine.dart';
import '../../workout/presentation/widgets/routine_card.dart';
import '../application/user_providers.dart' show userProfileProvider;

/// Lists BOTH the trainer-assigned plans and the athlete's self-created
/// routines for the authenticated athlete, in 2 stacked sections.
///
/// PRE-2026-06-30 only rendered trainer-assigned plans (REQ-PSR-020/021); the
/// self-created list was missing — athletes that built routines via the
/// Workout tab's "MIS RUTINAS" section had no way to see them from their
/// profile. This screen now surfaces both with explicit headers + empty
/// states.
///
/// Decisions (2026-06-19 conversation, confirmed 2026-06-30):
///   - **Always show both sections** (Opción B): the assigned section
///     stays visible even when the athlete has no trainer — its empty state
///     promotes finding one ("Buscar PF" CTA → `/coach`).
///   - **Active routine marker**: when the athlete has 2+ self-created
///     routines AND one is marked as active via `UserProfile.activeRoutineId`,
///     that card gets an "ACTIVA" chip (mirrors the visual contract of
///     `MisRutinasSection` in the Workout tab).
///   - **Read-only**: this screen does not host edit/archive/toggle-active
///     actions — those live in the Workout tab. Cards here are tap-to-open.
class ProfileRoutinesScreen extends ConsumerWidget {
  const ProfileRoutinesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final myUid = ref.watch(authStateChangesProvider).valueOrNull?.uid ?? '';

    final assignedAsync = ref.watch(assignedRoutinesProvider(myUid));
    final ownAsync = ref.watch(userCreatedRoutinesProvider(myUid));
    final activeId =
        ref.watch(userProfileProvider).valueOrNull?.activeRoutineId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: GestureDetector(
            onTap: () => context.pop(),
            behavior: HitTestBehavior.opaque,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionHeader(label: l10n.profileRoutinesAssignedHeader),
                const SizedBox(height: 12),
                _AssignedSection(
                  async: assignedAsync,
                  palette: palette,
                  l10n: l10n,
                ),
                const SizedBox(height: 28),
                _SectionHeader(label: l10n.profileRoutinesOwnHeader),
                const SizedBox(height: 12),
                _OwnSection(
                  async: ownAsync,
                  activeId: activeId,
                  palette: palette,
                  l10n: l10n,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Section header (RUTINAS ASIGNADAS / MIS RUTINAS PROPIAS) ────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Text(
      label,
      style: GoogleFonts.barlowCondensed(
        fontWeight: FontWeight.w700,
        fontSize: 13,
        letterSpacing: 1.4,
        color: palette.textMuted,
      ),
    );
  }
}

// ── Assigned-plans section ──────────────────────────────────────────────────

class _AssignedSection extends StatelessWidget {
  const _AssignedSection({
    required this.async,
    required this.palette,
    required this.l10n,
  });

  final AsyncValue<List<Routine>> async;
  final AppPalette palette;
  final AppL10n l10n;

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => _LoadingBlock(palette: palette),
      error: (_, __) => _ErrorBlock(
        message: 'No pudimos cargar tus rutinas. Intentá de nuevo.',
        palette: palette,
      ),
      data: (routines) {
        if (routines.isEmpty) {
          return _AssignedEmptyState(palette: palette, l10n: l10n);
        }
        return _RoutineList(
          routines: routines,
          activeId: null, // Trainer plans never carry the user's active marker.
        );
      },
    );
  }
}

class _AssignedEmptyState extends StatelessWidget {
  const _AssignedEmptyState({required this.palette, required this.l10n});
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

// ── Self-created routines section ───────────────────────────────────────────

class _OwnSection extends StatelessWidget {
  const _OwnSection({
    required this.async,
    required this.activeId,
    required this.palette,
    required this.l10n,
  });

  final AsyncValue<List<Routine>> async;
  final String? activeId;
  final AppPalette palette;
  final AppL10n l10n;

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => _LoadingBlock(palette: palette),
      error: (_, __) => _ErrorBlock(
        message: 'No pudimos cargar tus rutinas. Intentá de nuevo.',
        palette: palette,
      ),
      data: (routines) {
        if (routines.isEmpty) {
          return _OwnEmptyState(palette: palette, l10n: l10n);
        }
        // The ACTIVA chip only carries meaning with 2+ routines (with a
        // single routine the activation is implicit) — matches the same
        // contract enforced in MisRutinasSection.
        final showActiveBadge = routines.length > 1;
        return _RoutineList(
          routines: routines,
          activeId: showActiveBadge ? activeId : null,
        );
      },
    );
  }
}

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

// ── Routine list (shared between both sections) ─────────────────────────────

class _RoutineList extends StatelessWidget {
  const _RoutineList({required this.routines, required this.activeId});

  final List<Routine> routines;

  /// `null` for the assigned section. For the own section, holds the active
  /// routine id ONLY when `routines.length > 1` (the contract enforced by
  /// `MisRutinasSection`). The matching card renders an "ACTIVA" chip.
  final String? activeId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < routines.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _RoutineRow(
            routine: routines[i],
            isActive: activeId != null && routines[i].id == activeId,
          ),
        ],
      ],
    );
  }
}

class _RoutineRow extends StatelessWidget {
  const _RoutineRow({required this.routine, required this.isActive});
  final Routine routine;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    if (!isActive) return RoutineCard(routine: routine);
    // When active, stack the chip in the corner without rewriting the card.
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Stack(
      children: [
        RoutineCard(routine: routine),
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            key: const Key('profile_routines_active_chip'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(9999),
              border: Border.all(color: palette.accent.withValues(alpha: 0.5)),
            ),
            child: Text(
              l10n.profileRoutinesActiveChip,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 1.2,
                color: palette.accent,
              ),
            ),
          ),
        ),
      ],
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
