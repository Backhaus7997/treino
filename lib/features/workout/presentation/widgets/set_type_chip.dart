import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/tokens.dart';
import '../../domain/set_enums.dart';
import 'set_cell_box.dart';

/// Compact set-type affordance used at the start of each routine set row.
class SetTypeChip extends StatelessWidget {
  const SetTypeChip({
    super.key,
    required this.label,
    required this.type,
    required this.palette,
    required this.semanticsLabel,
    required this.onTap,
  });

  final String label;
  final SetType type;
  final AppPalette palette;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = switch (type) {
      SetType.warmup => palette.accent.withAlpha(40),
      SetType.drop => palette.highlight.withAlpha(40),
      SetType.failure => palette.danger.withAlpha(40),
      SetType.normal => palette.surfaceSubtle,
    };
    final foreground = switch (type) {
      SetType.warmup => palette.accentText,
      SetType.drop => palette.highlight,
      SetType.failure => palette.danger,
      SetType.normal => palette.textPrimary,
    };
    final border = switch (type) {
      SetType.warmup => palette.accent.withAlpha(100),
      SetType.drop => palette.highlight.withAlpha(100),
      SetType.failure => palette.danger.withAlpha(100),
      // Sin borde en el tipo normal: mismo criterio que la celda de al lado.
      // Los tipos especiales SÍ lo llevan — ahí el contorno de color es lo que
      // los distingue de un set común de un vistazo.
      SetType.normal => Colors.transparent,
    };

    return Semantics(
      button: true,
      label: semanticsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // La caja la pone `SetCellBox`, la misma que los campos de la fila:
        // tres widgets dibujando su propia versión de la misma geometría es
        // lo que los hacía divergir. Un tipo ESPECIAL suma su relleno y su
        // contorno de color encima — ahí el color es lo que lo distingue de un
        // set común de un vistazo.
        child: SetCellBox(
          // El tipo NORMAL usa el relleno común de la fila; los especiales
          // traen el suyo y su contorno de color, que es lo que los distingue
          // de un set común de un vistazo. Va en la caja y no en una capa
          // adentro: dos superficies pintadas es cómo empezó la divergencia.
          fill: type == SetType.normal ? null : background,
          borderColor: type == SetType.normal ? null : border,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.hairline,
            ),
            child: Text(
              label,
              style: GoogleFonts.barlowCondensed(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
