import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_palette.dart';
import '../auth/application/auth_providers.dart';
import '../auth/presentation/widgets/email_verification_banner.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final user = authState.valueOrNull;
    final showBanner = user != null && !user.emailVerified;

    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    return Column(
      children: [
        if (showBanner)
          const Padding(
            padding: EdgeInsets.all(12),
            child: EmailVerificationBanner(),
          ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'INICIO',
                  style: theme.textTheme.displayMedium?.copyWith(
                    color: palette.accent,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tu home base',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.textMuted,
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
