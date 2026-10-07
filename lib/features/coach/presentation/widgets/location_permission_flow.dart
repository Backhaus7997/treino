import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../application/location_permission_gateway.dart';
import 'location_flow_types.dart';
import 'location_permission_rationale_sheet.dart';

export 'location_flow_types.dart';

/// Punto único de entrada al pedido de ubicación «con contexto».
///
/// Decide qué mostrar según el estado REAL del permiso (Guideline 5.1.1(iv)) y,
/// cuando hace falta, PIDE EL PERMISO AL SO él mismo (tras el CONTINUAR), para
/// ver el resultado:
///
///  - **Servicios de ubicación apagados** → aviso que lleva a Ajustes;
///    `blocked`. Se evalúa primero.
///  - **Ya otorgado** → `granted`.
///  - **Aún no pedido** (`denied`/`unableToDetermine`) → mensaje previo con
///    UN solo botón CONTINUAR y, enseguida, el pedido al SO:
///    * otorgado → `granted`;
///    * `deniedForever` → el SO ya no puede preguntar: aviso de Ajustes (si
///      es [interactive]) y `blocked`;
///    * rechazado → `denied`.
///    En Android `checkPermission()` devuelve `denied` también tras «no volver
///    a preguntar»; sólo `requestPermission()` devuelve `deniedForever`. Por
///    eso el resultado del pedido se mira acá y no se descarta.
///  - **Denegado de forma permanente / restringido** (iOS lo informa ya en
///    `check`) → aviso informativo con acceso a Ajustes y salida para seguir
///    sin ubicación; `blocked`. Apple lo admite para una función que no anda
///    sin el permiso.
///
/// [interactive] distingue QUIÉN pidió el flujo. `true` (por defecto): lo
/// disparó una acción del usuario y el aviso de Ajustes es la respuesta
/// esperada. `false`: se abrió una pantalla y el flujo corre solo; ahí el
/// aviso sería un cartel insistente en cada apertura, así que se sigue en
/// silencio y sólo el primer pedido —el CONTINUAR previo al diálogo del SO—
/// se muestra, porque es un pedido en contexto.
///
/// Un error del plugin al consultar el estado se trata como «aún no pedido»
/// (y servicios encendidos). Si el PEDIDO lanza, se devuelve `granted` para
/// que el notifier del caller reintente y maneje el error a su manera.
Future<LocationFlowOutcome> presentLocationPermissionFlow(
  BuildContext context,
  LocationPermissionGateway gateway, {
  bool interactive = true,
  LocationPurpose purpose = LocationPurpose.trainers,
}) async {
  var servicesOn = true;
  try {
    servicesOn = await gateway.isServiceEnabled();
  } catch (_) {
    servicesOn = true;
  }
  if (!context.mounted) return LocationFlowOutcome.blocked;
  if (!servicesOn) {
    if (interactive) {
      await showLocationSettingsNoticeSheet(
        context,
        servicesOff: true,
        purpose: purpose,
        onOpenSettings: gateway.openLocationSettings,
      );
    }
    return LocationFlowOutcome.blocked;
  }

  LocationPermission status;
  try {
    status = await gateway.check();
  } catch (_) {
    status = LocationPermission.denied;
  }
  if (!context.mounted) return LocationFlowOutcome.blocked;

  switch (status) {
    case LocationPermission.always:
    case LocationPermission.whileInUse:
      return LocationFlowOutcome.granted;
    case LocationPermission.deniedForever:
      if (interactive) {
        await showLocationSettingsNoticeSheet(
          context,
          purpose: purpose,
          onOpenSettings: gateway.openSettings,
        );
      }
      return LocationFlowOutcome.blocked;
    case LocationPermission.denied:
    case LocationPermission.unableToDetermine:
      await showLocationPermissionRationaleSheet(context, purpose: purpose);
      if (!context.mounted) return LocationFlowOutcome.blocked;
      LocationPermission result;
      try {
        result = await gateway.request();
      } catch (_) {
        return LocationFlowOutcome.granted;
      }
      if (!context.mounted) return LocationFlowOutcome.blocked;
      switch (result) {
        case LocationPermission.always:
        case LocationPermission.whileInUse:
          return LocationFlowOutcome.granted;
        case LocationPermission.deniedForever:
          if (interactive) {
            await showLocationSettingsNoticeSheet(
              context,
              purpose: purpose,
              onOpenSettings: gateway.openSettings,
            );
          }
          return LocationFlowOutcome.blocked;
        case LocationPermission.denied:
        case LocationPermission.unableToDetermine:
          return LocationFlowOutcome.denied;
      }
  }
}

/// Aviso informativo para el permiso denegado de forma permanente o los
/// Servicios de ubicación apagados ([servicesOff]).
///
/// NO es un mensaje previo a un diálogo del SO (ese diálogo ya no existe):
/// explica qué hay que encender y lleva a Ajustes. Se puede cerrar
/// —«Seguir sin ubicación»— porque no hay ningún pedido que saltear.
Future<void> showLocationSettingsNoticeSheet(
  BuildContext context, {
  required Future<void> Function() onOpenSettings,
  bool servicesOff = false,
  LocationPurpose purpose = LocationPurpose.trainers,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _LocationSettingsNoticeSheet(
      onOpenSettings: onOpenSettings,
      servicesOff: servicesOff,
      purpose: purpose,
    ),
  );
}

class _LocationSettingsNoticeSheet extends StatelessWidget {
  const _LocationSettingsNoticeSheet({
    required this.onOpenSettings,
    required this.servicesOff,
    required this.purpose,
  });

  final Future<void> Function() onOpenSettings;
  final bool servicesOff;
  final LocationPurpose purpose;

  String _body(AppL10n l10n) => switch ((servicesOff, purpose)) {
        (true, LocationPurpose.trainers) => l10n.coachLocationServicesOffBody,
        (true, LocationPurpose.nearbyGyms) =>
          l10n.coachLocationServicesOffBodyGyms,
        (true, LocationPurpose.trainerDetect) =>
          l10n.coachLocationServicesOffBodyDetect,
        (false, LocationPurpose.trainers) =>
          l10n.coachLocationSettingsNoticeBody,
        (false, LocationPurpose.nearbyGyms) =>
          l10n.coachLocationSettingsNoticeBodyGyms,
        (false, LocationPurpose.trainerDetect) =>
          l10n.coachLocationSettingsNoticeBodyDetect,
      };

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
              servicesOff
                  ? l10n.coachLocationServicesOffTitle
                  : l10n.coachLocationSettingsNoticeTitle,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: AppTextSize.titleLarge,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(
              _body(l10n),
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
                  try {
                    await onOpenSettings();
                  } catch (_) {
                    // Si el SO no pudo abrir Ajustes, el aviso se cierra
                    // igual: no queda un error sin manejar ni un sheet
                    // atascado.
                  }
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
