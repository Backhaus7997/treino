import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';

/// Muestra el mensaje previo al permiso de ubicación del sistema operativo.
///
/// Se completa cuando el usuario toca CONTINUAR, y el caller tiene que pedir
/// el permiso al SO de inmediato (`requestPermission()` del notifier).
///
/// App Store Review Guideline 5.1.1(iv) (rechazo del build 1.0 (54)): el
/// mensaje previo tiene UN solo botón, redactado «Continuar», y el usuario
/// SIEMPRE pasa al pedido del sistema. Por eso:
///
///  - No hay «Ahora no» ni ningún otro botón que lo cierre sin pedir.
///  - No se puede cerrar arrastrando, tocando la barrera ni con «atrás»
///    (`isDismissible: false`, `enableDrag: false`, `PopScope`). Cualquier
///    cierre alternativo sería un «Ahora no» disfrazado. Hacer que el cierre
///    dispare el pedido tampoco sirve: el SO aparecería sin que el usuario
///    haya tocado nada.
///  - Si el SO ya no puede preguntar (denegado de forma permanente), este
///    mensaje NO se muestra: lo decide `presentLocationPermissionFlow`.
///
/// REQ-COACH-DISC-UI-011.
Future<void> showLocationPermissionRationaleSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (ctx) => const PopScope(
      canPop: false,
      child: _LocationRationaleSheet(),
    ),
  );
}

/// Class-style wrapper for [showLocationPermissionRationaleSheet] so callers
/// can use `LocationPermissionRationaleSheet.show(context)`.
class LocationPermissionRationaleSheet {
  const LocationPermissionRationaleSheet._();

  static Future<void> show(BuildContext context) =>
      showLocationPermissionRationaleSheet(context);
}

class _LocationRationaleSheet extends StatelessWidget {
  const _LocationRationaleSheet();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Container(
      decoration: BoxDecoration(
        color: palette.espresso,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s20,
        AppSpacing.s20,
        AppSpacing.s20,
        AppSpacing.s20,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(TreinoIcon.mapPin, size: 48, color: palette.accent),
            const SizedBox(height: AppSpacing.s14),
            Text(
              l10n.coachLocationSheetTitle,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: AppTextSize.titleLarge,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(
              l10n.coachLocationSheetBody,
              textAlign: TextAlign.center,
              style: GoogleFonts.barlow(
                fontSize: AppTextSize.body,
                color: palette.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.s20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: TreinoButtonTokens.foreground(context),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s14),
                ),
                child: Text(
                  l10n.coachLocationSheetContinue,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: AppTextSize.bodyLarge,
                    letterSpacing: 1.5,
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
