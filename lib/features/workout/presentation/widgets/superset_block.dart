import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';

/// Envoltorio visual del grupo de superserie en el editor de rutina.
///
/// Hasta #869 el bloque se pintaba con `highlight` al 4,7% de opacidad: contra
/// la card del día eso da una diferencia de 10 sobre 255 por canal, y en
/// pantalla el usuario no ve que dos ejercicios están agrupados. Acá el relleno
/// sube a [_kRelleno] (7,8%), que mide 16-17 en las dos paletas.
///
/// **El magenta va como FONDO, nunca como tinta.** Es el mismo diagnóstico que
/// motivó `AppPalette.accentText` para el mint: `highlight` pleno sobre este
/// relleno mide 3,85:1 en dark y 4,08:1 en light — por debajo del 4,5:1 que
/// WCAG AA pide para texto chico. El título va en `textPrimary` (17,6:1) y el
/// magenta se queda en el relleno, el borde y el ícono, que son gráficos y les
/// alcanza con el 3:1 de SC 1.4.11. Medido en
/// `test/app/theme/tokens/superset_block_contrast_test.dart`.
class SupersetBlock extends StatelessWidget {
  const SupersetBlock({
    required this.count,
    required this.children,
    this.reorderIndex,
    this.trailing,
    this.footer,
    super.key,
  });

  /// Cuántos ejercicios muestra el bloque. Es el número que el encabezado
  /// anuncia — el llamador ya filtró los ausentes en la semana en curso.
  final int count;

  /// Los editores de cada miembro, en orden.
  final List<Widget> children;

  /// Posición del bloque en el reorderable exterior. Null deja el header sin
  /// gesto de drag, pero conserva los controles accesibles de subir/bajar.
  final int? reorderIndex;

  /// Control opcional a la derecha del encabezado (los chevrons de reordenar).
  final Widget? trailing;

  /// Acción opcional al pie (agregar otro ejercicio a ESTE grupo).
  final Widget? footer;

  /// Relleno del bloque, sobre 255. Con `highlight` da 16-17 de diferencia por
  /// canal contra la card del día en ambas paletas.
  static const int _kRelleno = 20;

  /// Borde del bloque, sobre 255.
  ///
  /// Mide 1,86:1 (dark) y 2,15:1 (light) contra el relleno: por debajo del 3:1
  /// de SC 1.4.11, y llegar ahí pediría α215, un magenta casi pleno que se lee
  /// como jaula. Se acepta porque el borde **no es** el único canal que
  /// comunica la agrupación: están además el relleno, el encabezado de texto y
  /// los badges A1/A2. El precedente de #821 —`borderStrong` calibrado a 3:1—
  /// era el caso contrario: ahí el borde era el único límite.
  static const int _kBorde = 140;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s12),
      decoration: BoxDecoration(
        color: palette.highlight.withAlpha(_kRelleno),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.highlight.withAlpha(_kBorde)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (reorderIndex case final index?)
                ReorderableDragStartListener(
                  key: const Key('superset_drag_handle'),
                  index: index,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Icon(
                        TreinoIcon.dragHandle,
                        size: 18,
                        color: palette.highlight,
                      ),
                    ),
                  ),
                ),
              Icon(TreinoIcon.streak, size: 15, color: palette.highlight),
              const SizedBox(width: AppSpacing.hairline),
              Expanded(
                child: Text(
                  l10n.routineEditorSupersetHeader(count),
                  key: const Key('superset_block_header'),
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    letterSpacing: 1.2,
                    color: palette.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          ...children,
          if (footer != null) footer!,
        ],
      ),
    );
  }
}

/// Badge de orden dentro de una superserie: `A1`, `A2`, `A3`…
///
/// Es lo que dice en qué orden se ejecutan los ejercicios del grupo, y el único
/// lugar del bloque donde el orden aparece explícito.
class SupersetBadge extends StatelessWidget {
  const SupersetBadge({required this.position, super.key});

  /// Posición 0-based dentro del grupo. Se muestra como `A${position + 1}`.
  final int position;

  /// Lado del cuadrado, en dp. Es una marca, no un target: no se toca.
  static const double _kLado = 22;

  /// Relleno del badge sobre el bloque, sobre 255. Da 34-37 de diferencia por
  /// canal contra el relleno del bloque: se despega sin competir con el borde.
  static const int _kRelleno = 46;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // El handoff pedía radio 7. `AppRadius` es una escala CERRADA (12/16/20) y
    // agregar un valor para un componente es lo que esa escala existe para
    // evitar — mismo criterio que el chip del slice 1. Con `sm` sobre 22 dp el
    // badge queda circular, que para una marca de dos caracteres se lee igual.
    //
    // Sale 22x22 porque el agarre que lo contiene es una `Column` con
    // `mainAxisSize: min`, que pasa constraints LOOSE. Un `Container(width:)`
    // es una preferencia, no un techo: bajo constraints tight se estira, y ahí
    // no hay `Center(widthFactor: 1)` que lo salve. Si algún día el badge se
    // usa en un contenedor tight, va envuelto en un `UnconstrainedBox`.
    return Container(
      width: _kLado,
      height: _kLado,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.highlight.withAlpha(_kRelleno),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        'A${position + 1}',
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 11,
          height: 1.0,
          // textPrimary y no highlight: el magenta como tinta sobre este
          // relleno mide 3,2:1. Ver la nota de [SupersetBlock].
          color: palette.textPrimary,
        ),
      ),
    );
  }
}
