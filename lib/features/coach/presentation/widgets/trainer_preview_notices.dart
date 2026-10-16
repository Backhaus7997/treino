import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/tokens.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../application/trainer_discovery_providers.dart';

/// Marca de «VISTA PREVIA» arriba del perfil público cuando el que mira es el
/// propio PF (VER PREVIEW, #1498).
///
/// Sin esto la pantalla es idéntica a la que ve un alumno, con CONSULTAR y
/// PEDIR VÍNCULO a la vista: el PF los tocaba y no pasaba nada (ninguno actúa
/// sobre uno mismo), sin ninguna pista de que estaba mirando un ensayo.
class TrainerPreviewBanner extends StatelessWidget {
  const TrainerPreviewBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s12),
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: palette.accent),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(TreinoIcon.eye, size: 20, color: palette.accent),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.coachPreviewBannerTitle,
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: AppTextSize.body,
                      letterSpacing: 1.2,
                      color: palette.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.hairline),
                  Text(
                    l10n.coachPreviewBannerBody,
                    style: GoogleFonts.barlow(
                      fontSize: AppTextSize.bodyDense,
                      height: 1.4,
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Aviso al PF de que le falta cargar sus años de experiencia, bajo los stats
/// de la vista previa (#1498).
///
/// «AÑOS EXP —» es verdad —el dato no está— pero el PF no tiene cómo saber que
/// el que falta es suyo: RESEÑAS y ALUMNOS también muestran «—» y esos los
/// calcula el servidor. Los años los carga el PF a mano en EDITAR, así que acá
/// se lo dice y se lo lleva al formulario.
///
/// Al volver del formulario invalida el perfil público: el proveedor es
/// one-shot, y sin el `invalidate` la vista previa seguiría mostrando «—» con
/// el dato ya guardado.
class TrainerPreviewMissingExperienceNotice extends StatelessWidget {
  const TrainerPreviewMissingExperienceNotice({
    super.key,
    required this.trainerId,
  });

  final String trainerId;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Material(
      color: palette.bgCard,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () async {
          // El container se toma ANTES del await: al volver el `context` puede
          // ya no estar montado.
          final container = ProviderScope.containerOf(context);
          await context.push<void>('/profile/edit-trainer');
          container.invalidate(trainerByIdProvider(trainerId));
        },
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.s12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Icon(TreinoIcon.infoCircle, size: 20, color: palette.accent),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Text(
                  l10n.coachPreviewMissingExperience,
                  style: GoogleFonts.barlow(
                    fontSize: AppTextSize.bodyDense,
                    height: 1.4,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Icon(TreinoIcon.forward, size: 16, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
