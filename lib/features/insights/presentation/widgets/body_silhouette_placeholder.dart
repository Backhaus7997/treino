import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';

/// Placeholder visual de la silueta muscular hasta que tengamos el asset
/// SVG real con regiones coloreables por grupo. Reusado entre la pantalla
/// de Insights y la card "Esta Semana" del Home.
///
/// Sigue el estilo Mint Magenta — fondo `bg`, border `border`, ícono
/// `tabWorkout` centrado en mint para sugerir "stats de entrenamiento".
class BodySilhouettePlaceholder extends StatelessWidget {
  const BodySilhouettePlaceholder({
    super.key,
    required this.width,
    required this.height,
    this.label,
  });

  final double width;
  final double height;

  /// Opcional — texto al pie del ícono (ej. "muscle map · próximamente").
  final String? label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border, width: 1),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            TreinoIcon.tabWorkout,
            size: height * 0.45,
            color: palette.accent.withValues(alpha: 0.7),
          ),
          if (label != null) ...[
            const SizedBox(height: 8),
            Text(
              label!,
              textAlign: TextAlign.center,
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: 12,
                color: palette.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
