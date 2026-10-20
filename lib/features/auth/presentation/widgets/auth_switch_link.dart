import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/tokens.dart';

/// Cambio entre Login y Registro al pie: pregunta en gris y, debajo, la acción
/// en negrita. Todo el bloque es un solo blanco táctil (≥ 48 pt) anunciado
/// como un único botón.
class AuthSwitchLink extends StatelessWidget {
  const AuthSwitchLink({
    super.key,
    required this.prompt,
    required this.action,
    required this.onTap,
  });

  final String prompt;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Semantics(
      button: true,
      container: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  prompt,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.barlow(
                    fontSize: AppTextSize.body,
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  action,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.barlow(
                    fontSize: AppTextSize.bodyLarge,
                    fontWeight: FontWeight.w700,
                    color: palette.accentText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
