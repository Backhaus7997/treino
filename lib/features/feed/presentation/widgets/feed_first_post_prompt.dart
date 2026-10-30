import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';

/// Invitación a publicar, al pie del vacío de AMIGOS.
///
/// Sin posts de quienes seguís, el vacío eran el mensaje y el carrusel de
/// sugerencias pegados arriba, y el resto del viewport en blanco. Llenarlo con
/// "actividad de amigos" no sirve justo en el caso que más se ve —seguís a
/// poca gente o a nadie—, así que el hueco lo ocupa lo único que siempre se
/// puede hacer desde acá: publicar vos.
///
/// Va DESPUÉS de las sugerencias, no antes: seguir gente es la salida
/// principal del vacío y no tiene que quedar empujada para abajo.
class FeedFirstPostPrompt extends StatelessWidget {
  const FeedFirstPostPrompt({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Padding(
      key: const Key('feed_first_post_prompt'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s20),
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: palette.textMuted.withValues(alpha: 0.12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.feedFirstPostTitle,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: AppTextSize.title,
                letterSpacing: 0.8,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              l10n.feedFirstPostBody,
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: AppTextSize.body,
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.s18),
            ElevatedButton.icon(
              key: const Key('feed_first_post_button'),
              onPressed: () => context.push('/feed/create'),
              icon: const Icon(TreinoIcon.plus, size: 18),
              label: Text(l10n.feedFirstPostCta),
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.accent,
                // Ink invariante: `palette.bg` sobre el mint da 1.57:1 en light.
                foregroundColor: TreinoButtonTokens.foreground(context),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                textStyle: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: AppTextSize.bodyLarge,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
