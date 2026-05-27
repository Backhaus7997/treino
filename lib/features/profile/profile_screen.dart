import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_palette.dart';
import '../../core/utils/k_formatter.dart';
import '../auth/application/auth_providers.dart';
import '../auth/presentation/auth_strings.dart';
import 'application/profile_stats_providers.dart';
import 'application/user_providers.dart';
import 'domain/user_role.dart';
import 'presentation/widgets/profile_avatar_card.dart';
import 'presentation/widgets/profile_cuenta_section.dart';
import 'presentation/widgets/profile_header.dart';
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
          _OwnProfileStatsRow(palette: palette, theme: theme),
          const ProfileAvatarCard(),
          const ProfileCuentaSection(),
          // ── Legacy "Cerrar sesión" footer — intentional duplication ─────────
          // Kept through PR#1..PR#3 so sign-out is never broken mid-chain.
          // Removed in PR#4 the same commit the real Settings screen ships.
          // Per ADR-PSR-008.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: TextButton(
              onPressed: () =>
                  ref.read(authNotifierProvider.notifier).signOut(),
              child: Text(
                AuthStrings.profileSignOut, // i18n: Fase 6 Etapa 3
                style: TextStyle(color: palette.textMuted),
              ),
            ),
          ),
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
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
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: palette.textMuted,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
