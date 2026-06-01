import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import 'profile_section_tile.dart';

/// Renders a labelled group of [ProfileSectionTile]s inside a single shared
/// container with hairline dividers between consecutive tiles. Matches the
/// mockup's "one box per section" treatment for CUENTA and similar groups.
///
/// Each tile MUST be passed with `inGroup: true` so it skips its own border.
/// // i18n: Fase 6 Etapa 3
class ProfileSectionGroup extends StatelessWidget {
  const ProfileSectionGroup({
    super.key,
    required this.title,
    required this.tiles,
  });

  /// Uppercase section label rendered above the group (e.g. "CUENTA", "SESIÓN").
  final String title;

  /// Tiles to stack inside the single shared container. Each tile must already
  /// be constructed with `inGroup: true`.
  final List<ProfileSectionTile> tiles;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // Interleave tiles with hairline dividers (1px, muted) so the visual
    // grouping is unambiguous without growing the gap between rows.
    final children = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      if (i > 0) {
        children.add(
          Container(
            height: 1,
            color: palette.textMuted.withValues(alpha: 0.10),
          ),
        );
      }
      children.add(tiles[i]);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              title, // i18n: Fase 6 Etapa 3
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 1.4,
                color: palette.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: palette.textMuted.withValues(alpha: 0.12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
