import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_palette.dart';
import '../../core/utils/k_formatter.dart';
import '../../core/widgets/treino_icon.dart';
import '../auth/application/auth_providers.dart';
import 'application/profile_stats_providers.dart';
import 'application/user_providers.dart';
import 'domain/user_role.dart';
import 'presentation/widgets/eliminar_cuenta_sheet.dart';
import 'presentation/widgets/profile_avatar_card.dart';
import 'presentation/widgets/profile_cuenta_section.dart';
import 'presentation/widgets/profile_header.dart';
import 'presentation/widgets/profile_section_group.dart';
import 'presentation/widgets/profile_section_tile.dart';
import 'presentation/widgets/profile_trainer_section.dart';
import 'trainer_profile_view.dart';

/// Role-aware profile screen.
///
/// - Trainer → [TrainerProfileView] (matches docs/app-trainer/screens/perfil).
/// - Athlete (default) → existing rewrite chain (PR#1..PR#3 / Fase 3 Etapa 7):
///   header + stats + avatar card + cuenta section + legacy footer sign out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserRole? role = ref.watch(
      userProfileProvider.select((async) => async.valueOrNull?.role),
    );

    // Default to athlete (dominant role, matches HomeScreen/WorkoutScreen).
    return role == UserRole.trainer
        ? const TrainerProfileView()
        : const _AthleteProfile();
  }
}

/// Athlete profile — original [ProfileScreen] body extracted intact.
class _AthleteProfile extends ConsumerWidget {
  const _AthleteProfile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Column(
        children: [
          const ProfileHeader(),
          // Avatar card BEFORE stats — mockup parity 2026-06-01 polish pass.
          // Visual hierarchy: header → identity (who I am) → stats (what I did).
          const ProfileAvatarCard(),
          _OwnProfileStatsRow(palette: palette, theme: theme),
          const ProfileCuentaSection(),
          // Sección "ENTRENADOR" condicional — solo visible cuando
          // role == trainer. Tile que abre /profile/edit-trainer para
          // editar perfil público multi-location (Fase 6 Etapa 0 PR#3).
          const ProfileTrainerSection(),
          // ── Sesión section — PR#4 v2 pivot 2026-05-28 ────────────────────
          // Sign-out + account deletion grouped in one boxed section, mockup
          // parity polish 2026-06-01. Settings as a dedicated surface stays
          // deferred to a future SDD (notifications, theme, language).
          ProfileSectionGroup(
            title: 'SESIÓN', // i18n: Fase 6 Etapa 3
            tiles: [
              ProfileSectionTile(
                icon: TreinoIcon.signOut,
                title: 'Cerrar sesión', // i18n: Fase 6 Etapa 3
                inGroup: true,
                onTap: () => ref.read(authNotifierProvider.notifier).signOut(),
              ),
              ProfileSectionTile(
                icon: TreinoIcon.trash,
                title: 'Eliminar cuenta', // i18n: Fase 6 Etapa 3
                destructive: true,
                inGroup: true,
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  backgroundColor: palette.bgCard,
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(18)),
                  ),
                  isScrollControlled: true,
                  builder: (_) => const EliminarCuentaSheet(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ── Stats row ─────────────────────────────────────────────────────────────────

class _OwnProfileStatsRow extends ConsumerWidget {
  const _OwnProfileStatsRow({
    required this.palette,
    required this.theme,
  });

  final AppPalette palette;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(userSessionStatsProvider);

    // Mockup parity 2026-06-01 polish: wrap in a card with light border +
    // vertical dividers between the 3 stats. Numbers prominent, label small
    // beneath (was the inverse in the pre-polish layout).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Container(
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: palette.textMuted.withValues(alpha: 0.12),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: IntrinsicHeight(
          child: Row(
            children: [
              _StatTile(
                label: 'SESIONES', // i18n: Fase 6 Etapa 3
                value: statsAsync.when(
                  data: (s) => s.totalSessions.toString(),
                  loading: () => '--',
                  error: (_, __) => '--',
                ),
                valueColor: palette.accent,
                theme: theme,
                palette: palette,
              ),
              _StatDivider(palette: palette),
              _StatTile(
                label: 'VOLUMEN KG', // i18n: Fase 6 Etapa 3
                value: statsAsync.when(
                  data: (s) => kFormat(s.totalVolumeKg),
                  loading: () => '--',
                  error: (_, __) => '--',
                ),
                valueColor: palette.accent,
                theme: theme,
                palette: palette,
              ),
              _StatDivider(palette: palette),
              _StatTile(
                label: 'RACHA', // i18n: Fase 6 Etapa 3
                value: statsAsync.when(
                  data: (s) => s.streak.toString(),
                  loading: () => '--',
                  error: (_, __) => '--',
                ),
                valueColor: palette.highlight,
                theme: theme,
                palette: palette,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: palette.textMuted.withValues(alpha: 0.18),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.theme,
    required this.palette,
  });

  final String label;
  final String value;
  final Color valueColor;
  final ThemeData theme;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    // Mockup parity 2026-06-01: number prominent ON TOP, label small below
    // (previous order was inverted). Value font bumped to headlineMedium for
    // the visual weight the mockup uses (143 / 92k / 12 read first).
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: palette.textMuted,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
