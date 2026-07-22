import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../l10n/app_l10n.dart';
import '../../application/routine_providers.dart';
import 'level_filter_pills.dart';
import 'routine_card.dart';
import 'ver_mas_cell.dart';

/// Number of routine cards shown before the "Ver más" cell. When the user
/// taps Ver más, the section expands to show all routines and the Ver más
/// cell disappears.
///
/// Keep this odd: the Ver más cell sizes itself by filling the height of the
/// card it shares a 2-up row with (see the grid [Table] below) — an odd limit
/// guarantees it always lands next to a card, never alone in a row.
const int _kCollapsedLimit = 3;

class PlantillasSection extends ConsumerStatefulWidget {
  const PlantillasSection({super.key});

  @override
  ConsumerState<PlantillasSection> createState() => _PlantillasSectionState();
}

class _PlantillasSectionState extends ConsumerState<PlantillasSection> {
  bool _expanded = false;

  /// Wraps a grid cell with the inter-row gap. The Ver más cell fills the row
  /// height so its dashed border matches the card next to it — same look the
  /// old Row(stretch) gave it, but resolved inside the table's single layout
  /// pass. Cards keep their natural (deterministic) height.
  Widget _gridCell(Widget cell, {required bool lastRow}) {
    final padded = Padding(
      padding: EdgeInsets.only(bottom: lastRow ? 0 : 12),
      child: cell,
    );
    if (cell is VerMasCell) {
      return TableCell(
        verticalAlignment: TableCellVerticalAlignment.fill,
        child: padded,
      );
    }
    return padded;
  }

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
        const SizedBox(height: 10),
        const LevelFilterPills(),
        const SizedBox(height: 10),
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
            // Lay the cards out in manual rows of two instead of a GridView.
            // SliverGridDelegateWithFixedCrossAxisCount forces every cell to a
            // single hard-coded height (width / childAspectRatio): too short
            // for the card content — the subtitle overflowed — and it reserved
            // phantom vertical space that pushed HISTORIAL down.
            //
            // The rows live in a single-pass Table, NOT in per-row
            // IntrinsicHeight wrappers: IntrinsicHeight re-ran a dry-layout of
            // the whole row subtree every time a row re-entered the viewport,
            // and expanded the row count scales with the catalog — that extra
            // per-frame work janked the outer ListView scroll (#402). Equal
            // heights now come for free: reserveTitleLines makes every card
            // lay out at the same deterministic height, and the Ver más cell
            // fills its row via TableCellVerticalAlignment.fill.
            assert(
              _kCollapsedLimit.isOdd,
              'Ver más must share a 2-up row with a card (see _kCollapsedLimit '
              'doc) — alone in a row, its fill cell collapses to height 0.',
            );
            final cells = <Widget>[
              for (var i = 0; i < visibleCount; i++)
                RoutineCard(
                  routine: routines[i],
                  variant: routines[i].id.hashCode % 3 == 0
                      ? RoutineCardVariant.highlight
                      : RoutineCardVariant.accent,
                  reserveTitleLines: true,
                ),
              if (showVerMas)
                VerMasCell(onTap: () => setState(() => _expanded = true)),
            ];

            return Table(
              columnWidths: const {
                0: FlexColumnWidth(),
                1: FixedColumnWidth(12),
                2: FlexColumnWidth(),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.top,
              children: [
                for (var row = 0; row < cells.length; row += 2)
                  TableRow(
                    children: [
                      _gridCell(cells[row], lastRow: row + 2 >= cells.length),
                      const SizedBox.shrink(),
                      if (row + 1 < cells.length)
                        _gridCell(
                          cells[row + 1],
                          lastRow: row + 2 >= cells.length,
                        )
                      else
                        const SizedBox.shrink(),
                    ],
                  ),
              ],
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
                  child: Text(AppL10n.of(context).plantillasRetryLabel),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
