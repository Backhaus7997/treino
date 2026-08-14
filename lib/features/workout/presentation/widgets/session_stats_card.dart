import 'package:flutter/material.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/motion/treino_fade_slide_in.dart';
import 'stat_tile.dart';

/// Agrupa las 4 métricas de una sesión en una sola tarjeta con divisores en
/// cruz, en vez de dejarlas como números sueltos flotando sobre el fondo.
///
/// Usa los mismos tokens que el resto de las tarjetas del resumen post-entreno
/// (`bgCard` + radio 16 + `border`) para que se lean como el mismo sistema.
///
/// Espera exactamente 4 tiles: se disponen 2×2 en el orden recibido.
class SessionStatsCard extends StatelessWidget {
  const SessionStatsCard({
    super.key,
    required this.tiles,
    this.animateTiles = false,
    this.entryDelay = Duration.zero,
  }) : assert(
          tiles.length == 4,
          'SessionStatsCard espera exactamente 4 tiles',
        );

  final List<StatTile> tiles;
  final bool animateTiles;
  final Duration entryDelay;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    Widget tileAt(int index) {
      final tile = tiles[index];
      if (!animateTiles) return tile;

      return TreinoFadeSlideIn(
        delay: entryDelay + AppMotion.stagger(index),
        child: tile,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          _StatsRow(left: tileAt(0), right: tileAt(1), palette: palette),
          Divider(height: 1, thickness: 1, color: palette.border),
          _StatsRow(left: tileAt(2), right: tileAt(3), palette: palette),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.left,
    required this.right,
    required this.palette,
  });

  final Widget left;
  final Widget right;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    // IntrinsicHeight para que el divisor vertical mida lo mismo que la fila:
    // sin altura fija, la tarjeta sigue funcionando con text scaling grande.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: Padding(padding: _cellPadding, child: left)),
          VerticalDivider(width: 1, thickness: 1, color: palette.border),
          Expanded(child: Padding(padding: _cellPadding, child: right)),
        ],
      ),
    );
  }

  // Escala de spacing del design system (8 · 12 · 14 · 18 · 20). 16 está
  // explícitamente prohibido — docs/design-system.md.
  static const _cellPadding = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 18,
  );
}
