import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/tokens.dart';
import 'auth_circle_back_button.dart';

/// Cabecera de Login y Registro: botón de volver a la izquierda y título
/// centrado en la misma fila.
class AuthScreenHeader extends StatelessWidget {
  const AuthScreenHeader({
    super.key,
    required this.title,
    required this.onBack,
  });

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          AuthCircleBackButton(onPressed: onBack),
          // El título se centra contra el ancho total: el hueco de la derecha
          // mide lo mismo que el botón, así un título largo o un texto escalado
          // nunca pisa la flecha.
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                fontSize: AppTextSize.title,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: palette.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}
