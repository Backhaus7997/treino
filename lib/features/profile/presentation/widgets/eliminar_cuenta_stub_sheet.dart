import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';

/// Stub bottom sheet for the "Eliminar cuenta" action.
///
/// Intentionally contains NO delete logic — this is a placeholder that shows
/// support contact info until full account deletion is implemented (Fase 6+).
/// SCENARIO-531: opens on tile tap.
/// SCENARIO-532: CANCELAR closes the sheet without any action.
/// // i18n: Fase 6 Etapa 3
class EliminarCuentaStubSheet extends StatelessWidget {
  const EliminarCuentaStubSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: palette.textMuted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Eliminar cuenta', // i18n: Fase 6 Etapa 3
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: palette.danger,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Próximamente vas a poder eliminar tu cuenta. '
              'Por ahora, contactanos a soporte@treino.app '
              'si necesitás hacerlo.', // i18n: Fase 6 Etapa 3
              textAlign: TextAlign.center,
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: 14,
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'CANCELAR', // i18n: Fase 6 Etapa 3
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: palette.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
