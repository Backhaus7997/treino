import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_palette.dart';
import '../auth/application/auth_providers.dart';
import '../auth/presentation/auth_strings.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    return Center(
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
            onPressed: () => ref.read(authNotifierProvider.notifier).signOut(),
            child: Text(
              AuthStrings.profileSignOut,
              style: TextStyle(color: palette.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
