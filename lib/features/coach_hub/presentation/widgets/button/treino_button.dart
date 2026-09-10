import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../../../../app/theme/tokens/components/treino_button_tokens.dart';
import '../../../../../app/theme/tokens/components/treino_focus_tokens.dart';
import '../../../../../app/theme/tokens/primitives.dart';
import '../../../../../core/widgets/treino_icon.dart';
import '../preview_wrapper.dart';
import '../treino_interactive_state.dart';

@Preview(name: 'Button — variantes (md)', wrapper: coachHubPreviewWrapper)
Widget treinoButtonVariantsPreview() => const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TreinoButton(label: 'Guardar', onPressed: _noop),
        SizedBox(width: AppSpacing.s12),
        TreinoButton(
          label: 'Pago',
          variant: TreinoButtonVariant.secondary,
          icon: TreinoIcon.money,
          onPressed: _noop,
        ),
        SizedBox(width: AppSpacing.s12),
        TreinoButton(
          label: 'Cancelar',
          variant: TreinoButtonVariant.ghost,
          onPressed: _noop,
        ),
      ],
    );

@Preview(name: 'Button — sm + deshabilitado', wrapper: coachHubPreviewWrapper)
Widget treinoButtonSmallPreview() => const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TreinoButton(
          label: 'Chat',
          size: TreinoButtonSize.sm,
          variant: TreinoButtonVariant.secondary,
          icon: TreinoIcon.chat,
          onPressed: _noop,
        ),
        SizedBox(width: AppSpacing.s12),
        TreinoButton(label: 'Sin acción', onPressed: null),
        SizedBox(width: AppSpacing.s12),
        TreinoIconButton(
          icon: TreinoIcon.trash,
          tooltip: 'Eliminar',
          onPressed: _noop,
        ),
      ],
    );

void _noop() {}

/// Botón del kit Coach Hub Web.
///
/// POR QUÉ EXISTE. El kit tenía `avatar`, `data_table`, `dialog`,
/// `empty_state`, `filter_chips`, `kpi_card`, `list_row`, `pager`,
/// `section_header`, `section_hero`, `skeleton` y `treino_dropdown` — y ningún
/// `button`. `TreinoButtonTokens` existía desde el principio, pero suelto: sin
/// widget que lo encapsulara, cada pantalla se armaba su
/// `OutlinedButton`/`TextButton`/`ElevatedButton` a mano.
///
/// El resultado, medido: **154 botones Material crudos en `coach_hub`** (56
/// `TextButton`, 41 `IconButton`, 28 `ElevatedButton`, 25 `OutlinedButton`, 4
/// `FilledButton`). Sólo en `alumno_detail_screen.dart` conviven **siete
/// paddings distintos y seis tamaños de ícono**, el botón de confirmar es a
/// veces `FilledButton` y a veces `ElevatedButton`, el mismo ícono de eliminar
/// aparece en cuatro tamaños, y de 59 botones apenas 6 acotan su tap target
/// —los otros 53 arrastran los 48 px de Material 3, invisibles pero contando
/// para el layout—. Dos botones contiguos del header del detalle, con el mismo
/// padding declarado, reportaban cajas de alto distinto.
///
/// Eso no se arregla botón por botón. Se arregla teniendo uno.
///
/// QUÉ GARANTIZA, por construcción y no por disciplina:
/// - UN padding y UN alto por tamaño ([TreinoButtonSize]).
/// - UN tap target: el alto del tamaño, sin el `_InputPadding` de Material 3.
/// - UN anillo de foco, vía [TreinoFocusTokens].
/// - Hover que NO anima — un puntero es manipulación directa (lo fija además
///   el guard `no_animated_hover_scan_test.dart`).
/// - Deshabilitado que se ve deshabilitado y no recibe el puntero.
///
/// ```dart
/// TreinoButton(
///   label: 'Registrar pago',
///   icon: TreinoIcon.money,
///   variant: TreinoButtonVariant.secondary,
///   size: TreinoButtonSize.sm,
///   onPressed: () => registrarPago(context, ref, athleteId),
/// )
/// ```
class TreinoButton extends StatelessWidget {
  const TreinoButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = TreinoButtonVariant.primary,
    this.size = TreinoButtonSize.md,
    this.icon,
    this.expand = false,
    this.semanticsLabel,
  });

  final String label;

  /// `null` deshabilita el botón — misma convención que
  /// [TreinoInteractiveState], que resuelve `disabled` mirando si hay `onTap`.
  final VoidCallback? onPressed;

  final TreinoButtonVariant variant;
  final TreinoButtonSize size;

  /// Ícono opcional a la izquierda del label. Su tamaño lo decide [size]: es
  /// justamente lo que no pasaba cuando cada llamador elegía el suyo.
  final IconData? icon;

  /// `true` para que ocupe el ancho disponible (diálogos, formularios).
  final bool expand;

  /// Label para el lector de pantalla cuando el visible no alcanza.
  ///
  /// Se aplica con `excludeSemantics`, así que reemplaza al texto en vez de
  /// sumarse a él: sin eso el lector dice el nombre dos veces, que es
  /// exactamente el bug que tenían los items del sidebar.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final visual = TreinoButtonTokens.of(context, variant);
    final focus = TreinoFocusTokens.of(context);

    return Semantics(
      button: true,
      label: semanticsLabel,
      excludeSemantics: semanticsLabel != null,
      child: TreinoInteractiveState(
        onTap: onPressed,
        builder: (ctx, states) {
          final on = states.hovered || states.pressed;
          // Deshabilitado: mismo layout, medio tono. No se esconde ni se
          // achica — un botón que cambia de tamaño al deshabilitarse mueve
          // todo lo que tiene al lado.
          final opacity = states.disabled ? 0.4 : 1.0;

          return Opacity(
            opacity: opacity,
            child: Container(
              height: size.height,
              width: expand ? double.infinity : null,
              padding: EdgeInsets.symmetric(horizontal: size.paddingH),
              decoration: BoxDecoration(
                color: states.disabled
                    ? visual.background
                    : (on ? visual.hoverBackground : visual.background),
                borderRadius:
                    BorderRadius.circular(TreinoButtonTokens.borderRadius),
                border: Border.all(
                  color: on ? visual.hoverBorderColor : visual.borderColor,
                ),
                boxShadow: states.focused
                    ? [
                        BoxShadow(
                          color: focus.ring.withValues(alpha: 0.5),
                          spreadRadius: TreinoFocusTokens.ringWidth,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: size.iconSize, color: visual.foreground),
                    const SizedBox(width: TreinoButtonSize.gap),
                  ],
                  // `Flexible` + ellipsis: un label más largo que su caja
                  // trunca el TEXTO, no la app. El header de la tabla ya se
                  // comió esa lección.
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppFonts.barlow,
                        fontWeight: AppFonts.w600,
                        fontSize: size.fontSize,
                        color: visual.foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Botón de sólo ícono del kit — caja cuadrada del alto de [size].
///
/// Reemplaza a los `IconButton` sueltos, que con `visualDensity` y
/// `tapTargetSize` mezclados terminaban midiendo cualquier cosa: los cuatro de
/// la fila del roster reportaban 24x24 y quedaban PEGADOS, sin un píxel entre
/// blancos de click.
///
/// La caja es cuadrada por construcción, así que una fila de estos alinea sola.
/// La separación entre varios la pone quien los agrupa: el botón no decide su
/// margen.
class TreinoIconButton extends StatelessWidget {
  const TreinoIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.variant = TreinoButtonVariant.ghost,
    this.size = TreinoButtonSize.sm,
    this.color,
  });

  final IconData icon;

  /// Obligatorio, y también es el nombre accesible: un botón que sólo muestra
  /// un ícono y no se nombra es invisible para un lector de pantalla.
  final String tooltip;

  final VoidCallback? onPressed;
  final TreinoButtonVariant variant;
  final TreinoButtonSize size;

  /// Color del ícono cuando el de la variante no sirve (p. ej. `danger`).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final visual = TreinoButtonTokens.of(context, variant);
    final focus = TreinoFocusTokens.of(context);

    return Tooltip(
      message: tooltip,
      // El nombre accesible lo pone el `Semantics` de abajo; sin esto el
      // lector lo diría dos veces.
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: TreinoInteractiveState(
          onTap: onPressed,
          builder: (ctx, states) {
            final on = states.hovered || states.pressed;
            return Opacity(
              opacity: states.disabled ? 0.4 : 1.0,
              child: Container(
                width: size.height,
                height: size.height,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: states.disabled
                      ? visual.background
                      : (on ? visual.hoverBackground : visual.background),
                  borderRadius:
                      BorderRadius.circular(TreinoButtonTokens.borderRadius),
                  border: Border.all(
                    color: on ? visual.hoverBorderColor : visual.borderColor,
                  ),
                  boxShadow: states.focused
                      ? [
                          BoxShadow(
                            color: focus.ring.withValues(alpha: 0.5),
                            spreadRadius: TreinoFocusTokens.ringWidth,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  icon,
                  size: size.iconSize,
                  color: color ?? visual.foreground,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
