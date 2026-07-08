import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_palette.dart';

/// Chip seleccionable de género en el step 3. Tres opciones: femenino, masculino,
/// otro. Cuando [selected] = true, fondo accent + texto ink. Inactiva: outline
/// + texto muted.
class GenderChip extends StatelessWidget {
  const GenderChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9999),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? palette.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(9999),
            border: Border.all(
              color: selected ? palette.accent : palette.border,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.barlowCondensed(
              color: selected ? palette.bg : palette.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}
