import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_palette.dart';
import '../../application/routine_providers.dart';
import 'level_filter_pills.dart';
import 'routine_card.dart';

class PlantillasSection extends ConsumerWidget {
  const PlantillasSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final filteredAsync = ref.watch(filteredRoutinesProvider);
    final filter = ref.watch(routinesLevelFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PLANTILLAS',
          style: theme.textTheme.titleMedium?.copyWith(
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        const LevelFilterPills(),
        const SizedBox(height: 14),
        filteredAsync.when(
          data: (routines) {
            if (routines.isEmpty) {
              final msg = filter == null
                  ? 'No hay plantillas todavía.'
                  : 'No hay plantillas para este nivel.';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  msg,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              );
            }
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.95,
              ),
              itemCount: routines.length,
              itemBuilder: (context, i) => RoutineCard(routine: routines[i]),
            );
          },
          loading: () => Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CircularProgressIndicator(color: palette.accent),
            ),
          ),
          error: (_, __) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hubo un error cargando las plantillas.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => ref.invalidate(routinesProvider),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
