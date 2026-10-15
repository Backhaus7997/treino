import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/components/treino_button_tokens.dart';
import '../../../../app/theme/tokens/primitives.dart';
import '../../../../core/widgets/treino_icon.dart';
import 'button/treino_button.dart';

/// Aviso discreto «Datos desactualizados · Reintentar».
///
/// Se muestra arriba (o junto) a datos que SIGUEN visibles pero cuyo stream
/// falló después de cargar. El reintento es del llamador — casi siempre
/// `ref.invalidate(<provider>)`, que re-suscribe.
///
/// Tokens: sólo [AppPalette] / [AppSpacing] / [AppTextSize] — nunca hex inline.
class StaleDataNotice extends StatelessWidget {
  const StaleDataNotice({super.key, required this.onRetry});

  /// Re-suscribe la fuente (típicamente `ref.invalidate(provider)`).
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Datos desactualizados', // i18n
      child: Padding(
        key: const Key('stale_data_notice'),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.s8,
          children: [
            Icon(
              TreinoIcon.warning,
              size: AppTextSize.bodyLarge,
              color: palette.warning,
            ),
            ExcludeSemantics(
              child: Text(
                'Datos desactualizados', // i18n
                style: TextStyle(
                  fontFamily: AppFonts.barlow,
                  fontSize: AppTextSize.body,
                  color: palette.textMuted,
                ),
              ),
            ),
            TreinoButton(
              label: 'Reintentar', // i18n
              variant: TreinoButtonVariant.ghostAccent,
              size: TreinoButtonSize.xs,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

/// Atajo: [StaleDataNotice] si [stale]; si no, un hueco vacío.
///
/// Devuelve SIEMPRE un widget (nunca se omite de la lista de hijos): un
/// `if (x) StaleDataNotice(...)` dentro de una `Column` corre una posición a
/// los hermanos que vienen después cuando el aviso aparece, y Flutter remonta
/// lo que no tiene key (un formulario perdería lo que el usuario está
/// escribiendo; una lista, su scroll). Con este atajo el hueco existe siempre.
Widget staleNoticeIf(bool stale, VoidCallback onRetry) =>
    stale ? StaleDataNotice(onRetry: onRetry) : const SizedBox.shrink();
