import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../application/location_permission_gateway.dart';
import 'location_permission_rationale_sheet.dart';

/// Punto único de entrada al pedido de ubicación «con contexto».
///
/// Devuelve `true` si el caller debe llamar ahora a `requestPermission()` del
/// notifier (que dispara el diálogo del SO si hace falta y adquiere la
/// posición), y `false` si no hay nada que pedir.
///
/// Decide qué mostrar según el estado REAL del permiso (Guideline 5.1.1(iv)):
///
///  - **Ya otorgado** → nada que mostrar; `true` (sólo adquiere la posición).
///  - **Aún no pedido** → mensaje previo con UN solo botón CONTINUAR, que
///    siempre lleva al pedido del SO; `true`.
///  - **Denegado de forma permanente / restringido** → el SO ya no puede
///    preguntar, así que un mensaje previo prometería un diálogo que no va a
///    aparecer. Se muestra un aviso informativo con acceso a Ajustes y una
///    salida para seguir sin ubicación; `false`. Apple lo admite
///    explícitamente para una función que no anda sin el permiso.
///
/// Un error del plugin al consultar el estado se trata como «aún no pedido»:
/// el pedido al SO es la fuente de verdad y no se pierde por eso.
Future<bool> presentLocationPermissionFlow(
  BuildContext context,
  LocationPermissionGateway gateway,
) async {
  LocationPermission status;
  try {
    status = await gateway.check();
  } catch (_) {
    status = LocationPermission.denied;
  }
  if (!context.mounted) return false;

  switch (status) {
    case LocationPermission.always:
    case LocationPermission.whileInUse:
      return true;
    case LocationPermission.deniedForever:
      await showLocationSettingsNoticeSheet(
        context,
        onOpenSettings: gateway.openSettings,
      );
      return false;
    case LocationPermission.denied:
    case LocationPermission.unableToDetermine:
      await showLocationPermissionRationaleSheet(context);
      return context.mounted;
  }
}

/// Aviso informativo para el permiso denegado de forma permanente.
///
/// NO es un mensaje previo a un diálogo del SO (ese diálogo ya no existe):
/// explica que la función necesita el permiso y lleva a Ajustes. Se puede
/// cerrar —«Seguir sin ubicación»— porque no hay ningún pedido que saltear.
Future<void> showLocationSettingsNoticeSheet(
  BuildContext context, {
  required Future<void> Function() onOpenSettings,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) =>
        _LocationSettingsNoticeSheet(onOpenSettings: onOpenSettings),
  );
}

class _LocationSettingsNoticeSheet extends StatelessWidget {
  const _LocationSettingsNoticeSheet({required this.onOpenSettings});

  final Future<void> Function() onOpenSettings;

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
      padding: const EdgeInsets.all(AppSpacing.s20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(TreinoIcon.mapPin, size: 48, color: palette.accent),
            const SizedBox(height: AppSpacing.s14),
            Text(
              l10n.coachLocationSettingsNoticeTitle,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: AppTextSize.titleLarge,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(
              l10n.coachLocationSettingsNoticeBody,
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
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  await onOpenSettings();
                  navigator.pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: TreinoButtonTokens.foreground(context),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s14),
                ),
                child: Text(
                  l10n.coachLocationSettingsNoticeOpenSettings,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: AppTextSize.bodyLarge,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                l10n.coachLocationSettingsNoticeContinueWithout,
                style: GoogleFonts.barlow(
                  fontSize: AppTextSize.body,
                  color: palette.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
