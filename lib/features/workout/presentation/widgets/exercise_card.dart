import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import 'superset_block.dart';

/// Relleno del agarre cuando la card es miembro de una superserie, sobre 255.
const int _kAgarreSuperserie = 40;

/// Collapsible presentation shell for one exercise in the routine editor.
class ExerciseCard extends StatelessWidget {
  const ExerciseCard({
    required this.title,
    required this.summary,
    required this.expanded,
    required this.onToggle,
    required this.menu,
    required this.child,
    this.hasError = false,
    this.supersetPosition,
    super.key,
  });

  final String title;
  final Widget summary;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget menu;
  final Widget child;
  final bool hasError;

  /// Posición 0-based dentro de una superserie, o null si el ejercicio es
  /// suelto. Cuando está, el agarre se tiñe de `highlight` y muestra el badge
  /// `A1`/`A2`: son las dos marcas que dicen "esta card es parte de un grupo"
  /// desde afuera del bloque que la envuelve.
  final int? supersetPosition;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final enSuperserie = supersetPosition != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
          decoration: BoxDecoration(
            color: enSuperserie
                ? palette.highlight.withAlpha(_kAgarreSuperserie)
                : palette.surfaceSubtle,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (enSuperserie) ...[
                SupersetBadge(position: supersetPosition!),
                const SizedBox(height: AppSpacing.hairline),
              ],
              Icon(
                TreinoIcon.dragHandle,
                size: 18,
                color: enSuperserie ? palette.highlight : palette.textFaint,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s12,
              AppSpacing.s12,
              AppSpacing.s12,
              AppSpacing.s8,
            ),
            decoration: BoxDecoration(
              color: palette.bg,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              // El borde NO se pinta de rojo aunque [hasError] sea true. Un
              // campo vacío llegó a marcar cinco cosas a la vez —celda, card,
              // meta, punto de la pestaña y ahora el pie—, y con 3 días × 5
              // ejercicios eso es una pantalla en rojo donde ninguna señal
              // manda. Quedan tres, una por escala: la CELDA dice qué campo
              // falta, el PUNTO de la pestaña en qué día está, y el PIE cuántos
              // quedan y cómo llegar. [hasError] sigue existiendo porque es lo
              // que hace que una card con problemas nazca desplegada.
              border: Border.all(color: palette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  key: const Key('exercise_card_header'),
                  onTap: onToggle,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.hairline,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: GoogleFonts.barlow(
                                  fontSize: 16,
                                  height: 1.15,
                                  fontWeight: FontWeight.w700,
                                  color: palette.textPrimary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: AppSpacing.hairline),
                              summary,
                            ],
                          ),
                        ),
                      ),
                      menu,
                    ],
                  ),
                ),
                if (expanded) ...[
                  const SizedBox(height: AppSpacing.s12),
                  // La key existe SOLO cuando la card está desplegada: es lo
                  // que deja a un test saber en qué estado está sin depender
                  // del contenido. Ver `expandirEjercicios` en los fixtures.
                  KeyedSubtree(
                    key: const Key('exercise_card_body'),
                    child: child,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
