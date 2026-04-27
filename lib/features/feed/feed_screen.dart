import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';

class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'FEED',
            style: theme.textTheme.displayMedium?.copyWith(
              color: palette.accent,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Amigos · Comunidad · Público',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
