import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_palette.dart';
import '../../core/utils/k_formatter.dart';
import '../auth/application/auth_providers.dart';
import '../auth/presentation/auth_strings.dart';
import 'application/profile_stats_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    return Column(
      children: [
        _OwnProfileStatsRow(palette: palette, theme: theme),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'PERFIL',
                  style: theme.textTheme.displayMedium?.copyWith(
                    color: palette.accent,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tu cuenta y ajustes',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () =>
                      ref.read(authNotifierProvider.notifier).signOut(),
                  child: Text(
                    AuthStrings.profileSignOut,
                    style: TextStyle(color: palette.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
            label: 'SESIONES',
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
            label: 'VOLUMEN KG',
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
            label: 'RACHA',
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
          const SizedBox(height: 4),
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
