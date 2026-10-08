import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/moderation/moderation_guard.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Encabezado de un paso del onboarding: titular y bajada.
///
/// Los tres pasos lo comparten para que el ritmo vertical sea el mismo en
/// todos: si cada uno armara el suyo, la pantalla «saltaría» al avanzar.
class OnboardingEncabezado extends StatelessWidget {
  const OnboardingEncabezado({
    super.key,
    required this.titulo,
    required this.cuerpo,
  });

  final String titulo;
  final String cuerpo;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: GoogleFonts.barlowCondensed(
            color: palette.textPrimary,
            fontSize: AppTextSize.display,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
            height: 1,
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        Text(
          cuerpo,
          style: GoogleFonts.barlow(
            color: palette.textMuted,
            fontSize: AppTextSize.body,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

/// Etiqueta en mayúsculas sobre un campo, igual que la de `AuthInput`.
class OnboardingEtiqueta extends StatelessWidget {
  const OnboardingEtiqueta(this.texto, {super.key});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: GoogleFonts.barlowCondensed(
        color: AppPalette.of(context).textMuted,
        fontSize: AppTextSize.caption,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
      ),
    );
  }
}

/// Mensaje de error inline, en `danger`.
class OnboardingError extends StatelessWidget {
  const OnboardingError(this.mensaje, {super.key});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return Text(
      mensaje,
      style: GoogleFonts.barlow(
        color: AppPalette.of(context).danger,
        fontSize: AppTextSize.bodyDense,
      ),
    );
  }
}

/// Texto para el error que dejó una escritura del onboarding.
///
/// La moderación tiene su copy propio; todo lo demás (permisos, red, un perfil
/// que cambió debajo) se dice igual: no se pudo guardar y se puede reintentar.
/// Nunca se muestra el texto de la excepción.
String mensajeDeErrorDeEscritura(AppL10n l10n, Object error) {
  if (error is ModerationBlockedException) return l10n.moderationBlockedMessage;
  return l10n.coachHubOnboardingSaveError;
}
