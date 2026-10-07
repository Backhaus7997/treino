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
///  - **Servicios de ubicación apagados** → no hay posición posible ni diálogo
///    del SO que mostrar: aviso que lleva a Ajustes; `false`. Se evalúa
///    primero, porque con los servicios apagados un CONTINUAR no produciría
///    nada visible.
///  - **Ya otorgado** → nada que mostrar; `true` (sólo adquiere la posición).
///  - **Aún no pedido** → mensaje previo con UN solo botón CONTINUAR, que
///    siempre lleva al pedido del SO; `true`.
///  - **Denegado de forma permanente / restringido** → el SO ya no puede
///    preguntar, así que un mensaje previo prometería un diálogo que no va a
///    aparecer. Se muestra un aviso informativo con acceso a Ajustes y una
///    salida para seguir sin ubicación; `false`. Apple lo admite
///    explícitamente para una función que no anda sin el permiso.
///
/// [interactive] distingue QUIÉN pidió el flujo. `true` (por defecto): lo
/// disparó una acción del usuario (chip «Distancia», «Activar ubicación»,
/// gimnasios cercanos) y el aviso de Ajustes es la respuesta esperada. `false`:
/// se abrió una pantalla y el flujo corre solo; ahí el aviso de Ajustes sería
/// un cartel insistente en cada apertura, así que se sigue en silencio
/// (`false`) y sólo el primer pedido —el CONTINUAR previo al diálogo del SO—
/// se muestra, porque es un pedido en contexto.
///
/// Un error del plugin al consultar el estado se trata como «aún no pedido»
/// (y servicios encendidos): el pedido al SO es la fuente de verdad y no se
/// pierde por eso.
Future<bool> presentLocationPermissionFlow(
  BuildContext context,
  LocationPermissionGateway gateway, {
  bool interactive = true,
}) async {
  var servicesOn = true;
  try {
    servicesOn = await gateway.isServiceEnabled();
  } catch (_) {
    servicesOn = true;
  }
  if (!context.mounted) return false;
  if (!servicesOn) {
    if (interactive) {
      await showLocationSettingsNoticeSheet(
        context,
        servicesOff: true,
        onOpenSettings: gateway.openLocationSettings,
      );
    }
    return false;
  }

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
      if (interactive) {
        await showLocationSettingsNoticeSheet(
          context,
          onOpenSettings: gateway.openSettings,
        );
      }
      return false;
    case LocationPermission.denied:
    case LocationPermission.unableToDetermine:
      await showLocationPermissionRationaleSheet(context);
      return context.mounted;
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
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _LocationSettingsNoticeSheet(
      onOpenSettings: onOpenSettings,
      servicesOff: servicesOff,
    ),
  );
}

class _LocationSettingsNoticeSheet extends StatelessWidget {
  const _LocationSettingsNoticeSheet({
    required this.onOpenSettings,
    required this.servicesOff,
  });

  final Future<void> Function() onOpenSettings;
  final bool servicesOff;

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
              servicesOff
                  ? l10n.coachLocationServicesOffBody
                  : l10n.coachLocationSettingsNoticeBody,
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
