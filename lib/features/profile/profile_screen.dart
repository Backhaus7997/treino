import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_palette.dart';
import '../../core/utils/k_formatter.dart';
import '../../core/widgets/treino_icon.dart';
import '../auth/application/auth_providers.dart';
import 'application/profile_stats_providers.dart';
import 'presentation/widgets/eliminar_cuenta_stub_sheet.dart';
import 'presentation/widgets/profile_avatar_card.dart';
import 'presentation/widgets/profile_cuenta_section.dart';
import 'presentation/widgets/profile_header.dart';
import 'presentation/widgets/profile_section_tile.dart';
import 'presentation/widgets/profile_trainer_section.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

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
          // Sección "ENTRENADOR" condicional — solo visible cuando
          // role == trainer. Tile que abre /profile/edit-trainer para
          // editar perfil público multi-location (Fase 6 Etapa 0 PR#3).
          const ProfileTrainerSection(),
          // ── Account actions — PR#4 v2 pivot 2026-05-28 ───────────────────
          // Sign-out and account deletion tiles live here directly.
          // Settings as a surface deferred to a future SDD (notifications,
          // theme, language). Per PR#4 pivot decision.
          ProfileSectionTile(
            icon: TreinoIcon.signOut,
            title: 'Cerrar sesión', // i18n: Fase 6 Etapa 3
            onTap: () => ref.read(authNotifierProvider.notifier).signOut(),
          ),
          ProfileSectionTile(
            icon: TreinoIcon.trash,
            title: 'Eliminar cuenta', // i18n: Fase 6 Etapa 3
            destructive: true,
            onTap: () => showModalBottomSheet<void>(
              context: context,
              backgroundColor: palette.bgCard,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              isScrollControlled: false,
              builder: (_) => const EliminarCuentaStubSheet(),
            ),
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
