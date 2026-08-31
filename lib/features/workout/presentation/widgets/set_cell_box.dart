import 'package:flutter/material.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';

/// La caja de una celda de la fila de set. **Única fuente de esa geometría.**
///
/// La fila mezcla tres cosas —el chip del número, los campos de KG/REPS y el
/// de TIEMPO—, y las tres se dibujaban por su cuenta: dos con `Container` +
/// `BoxDecoration` y una con `InputDecoration` + `OutlineInputBorder`. Iban
/// divergiendo de a poco, y en device se veían como familias distintas aunque
/// los números coincidieran. Costó tres rondas de correcciones; ahora hay un
/// solo lugar donde vive el alto, el radio, el relleno y el borde.
///
/// El borde SOLO aparece cuando hay algo que decir: la celda en edición y la
/// incompleta. En reposo el contorno se leía como una línea que cortaba la
/// fila en vez de integrarla.
class SetCellBox extends StatelessWidget {
  const SetCellBox({
    required this.child,
    this.focused = false,
    this.hasError = false,
    this.fill,
    this.borderColor,
    this.minWidth = kMinWidth,
    this.minHeight = kMinHeight,
    super.key,
  });

  final Widget child;
  final bool focused;
  final bool hasError;

  /// Relleno propio, para el chip de un tipo ESPECIAL de set. Null usa el
  /// relleno común. Va acá y no en un `DecoratedBox` adentro para que la caja
  /// siga siendo UNA sola: dos capas pintadas es cómo empezó la divergencia.
  final Color? fill;

  /// Contorno propio, mismo criterio que [fill]. Se ignora cuando la celda
  /// está enfocada o incompleta: esos estados mandan sobre la decoración.
  final Color? borderColor;

  final double minWidth;
  final double minHeight;

  /// Ancho mínimo. 44, no los 34 del handoff: 34 bajaba el área táctil de
  /// 1936 a 1632 px² sobre un control que se toca en cada set.
  static const double kMinWidth = 44;

  /// Alto mínimo. `minHeight` y no un alto fijo: con Dynamic Type grande el
  /// contenido crece, y un alto rígido lo recorta.
  static const double kMinHeight = 48;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final colorBorde = hasError
        ? palette.danger
        : focused
            ? palette.accent
            : (borderColor ?? Colors.transparent);

    return Container(
      constraints: BoxConstraints(minWidth: minWidth, minHeight: minHeight),
      decoration: BoxDecoration(
        color: fill ?? palette.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: colorBorde,
          width: hasError || focused ? 1.5 : 1.0,
        ),
      ),
      // Center con factores en 1 en vez de `alignment: center`: `alignment`
      // mete un Align, y un Align con constraints acotadas se estira a
      // llenarlas — la caja se comía el alto entero de la fila.
      child: Center(widthFactor: 1, heightFactor: 1, child: child),
    );
  }
}

/// La decoración que va DENTRO de una [SetCellBox].
///
/// El tema de la app pone `filled: true` con `fillColor: bgCard` para todo
/// `InputDecoration`. Sin apagarlo, el campo pinta una banda oscura encima de
/// la caja clara — y como mide menos que los 48 dp, esa banda se lee como una
/// línea negra a la altura del texto. Fue exactamente el bug que costó dos
/// intentos encontrar, así que vive acá y no copiado en cada campo.
InputDecoration setCellDecoration({
  required AppPalette palette,
  String? hint,
  bool hasError = false,
  EdgeInsets? padding,
}) =>
    InputDecoration(
      isDense: true,
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      contentPadding: padding ??
          const EdgeInsets.symmetric(horizontal: AppSpacing.hairline),
      hintText: hint,
      hintStyle: TextStyle(
        color: hasError ? palette.danger.withAlpha(180) : palette.textMuted,
      ),
    );
