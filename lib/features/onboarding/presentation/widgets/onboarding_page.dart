import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';

/// Una pantalla del tour: ícono grande, título condensed en mayúsculas y
/// cuerpo. Puramente presentacional — no sabe en qué tour vive ni cuál es el
/// paso siguiente, así que las slices 2 y 3 la reusan tal cual.
///
/// Scrollea por dentro a propósito: con escalado de texto del sistema al
/// máximo, un cuerpo de 3 líneas se vuelve de 8 y desbordaría la columna.
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.footer,
  });

  /// Ícono de la pantalla. Siempre un `TreinoIcon.X` — nunca PhosphorIcons
  /// directo (AGENTS.md regla 2).
  final IconData icon;

  final String title;
  final String body;

  /// Contenido opcional debajo del cuerpo (ej. el CTA de activar rankings).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: palette.border),
            ),
            child: Icon(icon, size: 34, color: palette.accent),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: GoogleFonts.barlowCondensed(
              color: palette.textPrimary,
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: GoogleFonts.barlow(
              color: palette.textMuted,
              fontSize: 16,
              fontWeight: FontWeight.w400,
              height: 1.45,
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: 20),
            footer!,
          ],
        ],
      ),
    );
  }
}
