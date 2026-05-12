import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';

class TrainerCoachView extends StatelessWidget {
  const TrainerCoachView({super.key});

  static const _labels = <String>[
    'DASHBOARD',
    'ALUMNOS',
    'AGENDA',
    'COMUNIDADES',
  ];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    return DefaultTabController(
      length: _labels.length,
      child: Column(
        children: [
          // TabBar at top — sub-navigation inside the outer Coach tab.
          // Indicator color uses accent (mint). Labels follow design system:
          // Barlow Condensed 700 UPPERCASE.
          TabBar(
            isScrollable: true,
            indicatorColor: palette.accent,
            labelColor: palette.textPrimary,
            unselectedLabelColor: palette.textMuted,
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
            labelStyle: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
            tabs: [for (final l in _labels) Tab(text: l)],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final l in _labels) _TrainerSubTabPlaceholder(label: l),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline placeholder per sub-tab. Centered label + "PRÓXIMAMENTE".
/// Pure widget — no data, no Riverpod, no I/O.
class _TrainerSubTabPlaceholder extends StatelessWidget {
  const _TrainerSubTabPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: theme.textTheme.displaySmall?.copyWith(
              color: palette.highlight,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'PRÓXIMAMENTE',
            style: theme.textTheme.labelLarge?.copyWith(
              color: palette.textMuted,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
