import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/tokens/tokens.dart';
import 'treino_icon.dart';

/// Aviso de error de un formulario que vive DENTRO de un bottom sheet.
///
/// Un `SnackBar` no sirve ahí: `ScaffoldMessenger` lo pinta en el Scaffold de
/// la pantalla de atrás, y el sheet —que se abre con `useRootNavigator: true`,
/// o sea en el overlay del root navigator— lo tapa. El usuario toca el botón y
/// no ve nada (#1490, #1495).
///
/// `liveRegion` hace que el lector de pantalla lo anuncie cuando aparece, que
/// es lo que hacía el SnackBar.
class FormInlineError extends StatelessWidget {
  const FormInlineError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(TreinoIcon.warning, size: 16, color: palette.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.barlow(
                fontSize: AppTextSize.bodyDense,
                fontWeight: FontWeight.w600,
                color: palette.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
