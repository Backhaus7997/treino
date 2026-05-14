import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_palette.dart';
import '../../application/routine_providers.dart';
import 'level_filter_pills.dart';
import 'routine_card.dart';
import 'ver_mas_cell.dart';

/// Number of routine cards shown before the "Ver más" cell. When the user
/// taps Ver más, the section expands to show all routines and the Ver más
/// cell disappears.
const int _kCollapsedLimit = 3;

class PlantillasSection extends ConsumerStatefulWidget {
  const PlantillasSection({super.key});

  @override
  ConsumerState<PlantillasSection> createState() => _PlantillasSectionState();
}

class _PlantillasSectionState extends ConsumerState<PlantillasSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
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
            // Show 3 cards + Ver más cell when collapsed AND there are more
            // than 3 routines. Otherwise show all routines and no Ver más
            // cell (nothing more to expand to).
            final hasMore = routines.length > _kCollapsedLimit;
            final showVerMas = hasMore && !_expanded;
            final visibleCount =
                showVerMas ? _kCollapsedLimit : routines.length;
            final itemCount = showVerMas ? visibleCount + 1 : visibleCount;

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.95,
              ),
              itemCount: itemCount,
              itemBuilder: (context, i) {
                if (showVerMas && i == visibleCount) {
                  return VerMasCell(
                    onTap: () => setState(() => _expanded = true),
                  );
                }
                final routine = routines[i];
                final variant = routine.id.hashCode % 3 == 0
                    ? RoutineCardVariant.highlight
                    : RoutineCardVariant.accent;
                return RoutineCard(routine: routine, variant: variant);
              },
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
