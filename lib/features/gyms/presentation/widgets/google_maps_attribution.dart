import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/primitives.dart';

/// Atribución textual exigida por la política de Google Places: el contenido
/// de Places mostrado fuera de un mapa de Google debe llevar «Google Maps»
/// visible, sin modificar y legible.
///
/// Es el nombre de marca: no se traduce, por eso es una constante y no una
/// clave ARB. Mostrala SOLO debajo de listas que rendericen resultados vivos
/// de Places (no con vacío, carga o error, ni con gimnasios de Firestore).
class GoogleMapsAttribution extends StatelessWidget {
  const GoogleMapsAttribution({super.key});

  static const String texto = 'Google Maps';

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Text(
      texto,
      textAlign: TextAlign.end,
      style: GoogleFonts.barlow(
        color: palette.textMuted,
        fontSize: AppTextSize.bodyDense,
      ),
    );
  }
}
