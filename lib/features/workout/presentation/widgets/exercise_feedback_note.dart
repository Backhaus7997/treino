import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/tokens.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../domain/exercise_feedback.dart';

/// Lo que el alumno reportó, del lado del que lo lee (#628).
///
/// Espejo visual de [CoachNote] —el mismo canal en la otra dirección— con una
/// diferencia deliberada: `kind: discomfort` NO se ve igual que un comentario.
/// El PF abre el historial de una sesión para leer números; una molestia tiene
/// que saltarle a la cara sin que la busque, o el feature no sirve para lo
/// único que importa, que es enterarse a tiempo.
///
/// Esa diferencia la carga sobre todo la PALABRA del tag ("MOLESTIA" vs
/// "COMENTARIO"), no el color del texto: el tint sobre su propio fondo al 8%
/// no llega ni a 2.5:1 en la paleta clara (ver el comentario de `tagColor` en
/// [build]).
///
/// ⚠️ El ícono y el borde ACOMPAÑAN, no distinguen por sí solos. Medido en las
/// dos paletas: en dark el tint da 8.99–10.79:1 y el borde 2.56–2.76, pero en
/// LIGHT el ícono cae a 1.50–2.21:1 (bajo el 3:1 que WCAG 1.4.11 pide para
/// gráficos) y el borde a 1.24–1.42. Peor: los dos fondos entre sí
/// (warning@8% vs accent@8%) son indistinguibles, 1.00–1.02:1. O sea que en
/// tema claro un daltónico —o cualquiera con la pantalla al sol— se entera por
/// el TEXTO o no se entera. Por eso el tag va con palabra propia y no es sólo
/// un punto de color, y por eso subirle el contraste al ícono/borde queda
/// anotado como deuda y no como "ya está resuelto".
///
/// Read-only en todas sus superficies. El canal es one-way en esta versión
/// (#628, "No entra"): para conversar está el chat.
class ExerciseFeedbackNote extends StatelessWidget {
  const ExerciseFeedbackNote({required this.feedback, super.key});

  final ExerciseFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final isDiscomfort = feedback.isDiscomfort;
    // `warning` y no `danger`: esto es "avisame", no "algo se rompió". Usar el
    // rojo de error para lo que el alumno cuenta lo convertiría en una alarma
    // clínica, y #628 dice explícitamente que este canal NO es un asistente
    // médico.
    final tint = isDiscomfort ? palette.warning : palette.accent;
    // El TEXTO del tag no puede ir en `tint`. Sobre su propio fondo
    // (`tint` al 8% compuesto sobre bg/bgCard) el mint mide 1.50:1 y el ámbar
    // 2.13:1 en la paleta CLARA — a 10 px es directamente ilegible, y AGENTS.md
    // §2 ya deja registrado que todo par donde `accent` sea fondo se mide en
    // las DOS paletas. `textPrimary` sobre ese mismo fondo da 15.95:1 (peor
    // caso, dark/bgCard) y 16.55:1 (peor caso, light). El semántico lo siguen
    // cargando el ícono, el borde y la PALABRA del tag, no el color del texto.
    final tagColor = palette.textPrimary;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppSpacing.s8),
      // `horizontal: 10` estaba fuera de la escala cerrada (AGENTS.md §2, y el
      // dartdoc de AppSpacing: el único sub-8 legítimo es `hairline`). Sube a
      // `s12`, el valor de la escala para padding interno de card, y el mismo
      // que ahora usa [CoachNote] — los dos lados del canal tienen que medir
      // igual, que es la razón por la que este change ya sacó a coach_note del
      // allowlist de radios crudos.
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: isDiscomfort
            ? Border.all(color: tint.withValues(alpha: 0.4))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isDiscomfort ? TreinoIcon.warning : TreinoIcon.chat,
                size: 12,
                color: tint,
              ),
              const SizedBox(width: AppSpacing.hairline),
              Text(
                isDiscomfort
                    ? l10n.exerciseFeedbackNoteTagDiscomfort
                    : l10n.exerciseFeedbackNoteTagComment,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: tagColor,
                ),
              ),
              if (feedback.setNumber != null) ...[
                const SizedBox(width: AppSpacing.s8),
                Text(
                  l10n.exerciseFeedbackNoteSetTag(feedback.setNumber!),
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ],
          ),
          if (feedback.text != null && feedback.text!.trim().isNotEmpty) ...[
            // `hairline` (4) y no `2`: el dartdoc de AppSpacing nombra
            // explícitamente a 2/4/6 como los números crudos que este token
            // existe para reemplazar, y esto es exactamente su caso de uso —
            // separación óptica título-a-cuerpo dentro del componente.
            const SizedBox(height: AppSpacing.hairline),
            Text(
              feedback.text!.trim(),
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: palette.textPrimary,
              ),
            ),
          ],
          if (feedback.photoUrl != null && feedback.photoUrl!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s8),
            _FeedbackPhoto(url: feedback.photoUrl!),
          ],
        ],
      ),
    );
  }
}

class _FeedbackPhoto extends StatelessWidget {
  const _FeedbackPhoto({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 140,
        height: 140,
        fit: BoxFit.cover,
        // Sin los memCache bounds, una foto de cámara entra entera en memoria
        // para pintarse en 140 px — y el PF puede tener varias abiertas en la
        // misma sesión (AGENTS.md regla 6).
        memCacheWidth: 280,
        memCacheHeight: 280,
        placeholder: (_, __) => Container(
          width: 140,
          height: 140,
          color: palette.bg,
        ),
        // Un 403 acá NO es raro: la URL con token vive dentro del documento, y
        // el objeto puede haberse borrado (cascade de cuenta) mientras el doc
        // sigue en una caché local. Vale más un placeholder que una excepción.
        errorWidget: (_, __, ___) => Container(
          width: 140,
          height: 140,
          color: palette.bg,
          child: Icon(TreinoIcon.image, color: palette.textMuted),
        ),
      ),
    );
  }
}
