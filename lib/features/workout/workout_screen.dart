import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_palette.dart';
import 'presentation/widgets/historial_section.dart';
import 'presentation/widgets/plantillas_section.dart';

class WorkoutScreen extends ConsumerWidget {
  const WorkoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No ref.watch here — sections own their own consumers.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        physics: const ClampingScrollPhysics(),
        children: const [
          PlantillasSection(),
          SizedBox(height: 20),
          _TuRutinaSection(),
          SizedBox(height: 20),
          HistorialSection(),
        ],
      ),
    );
  }
}

// Private placeholder sections — no logic, no tests, no providers.
class _TuRutinaSection extends StatelessWidget {
  const _TuRutinaSection();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TU RUTINA',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Text(
          'No tenés rutina asignada todavía.',
          style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted),
        ),
      ],
    );
  }
}
