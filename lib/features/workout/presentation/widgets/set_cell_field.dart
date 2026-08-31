import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/tokens.dart';
import '../../domain/set_limits.dart';
import 'bounded_number_formatter.dart';

/// Parsea el peso tal como lo tipea el atleta, aceptando coma o punto.
///
/// El teclado numérico de iOS ofrece coma en locales es-AR; el de Android,
/// punto. Los dos tienen que llegar al mismo double.
double? parseEditorWeight(String value) =>
    double.tryParse(value.replaceAll(',', '.'));

/// Celda numérica de la tabla de series del editor de rutina.
///
/// Reemplaza al `_NumberField` con underline de ~38-40 dp que vivía dentro de
/// `routine_editor_screen.dart`. Conserva su API, sus formatters y sus
/// callbacks: lo único que cambia es la decoración.
class SetCellField extends StatefulWidget {
  const SetCellField({
    super.key,
    required this.controller,
    required this.palette,
    this.onChanged,
    this.onDecimalChanged,
    this.decimal = false,
    this.hint,
    this.hasError = false,
    this.focusNode,
  }) : assert(
          decimal ? onDecimalChanged != null : onChanged != null,
          'decimal fields need onDecimalChanged; integer fields need onChanged',
        );

  final TextEditingController controller;
  final AppPalette palette;
  final String? hint;

  /// Focus node externo — las celdas del editor tienen uno propio para que su
  /// fila publique cuál se está editando en la barra de accesorio (#867).
  final FocusNode? focusNode;

  /// Callback entero, usado cuando [decimal] es false (reps, etc.).
  final void Function(int?)? onChanged;

  /// Callback double, usado cuando [decimal] es true (peso en kg).
  final void Function(double?)? onDecimalChanged;

  /// Cuando es true el campo acepta fraccionarios (ej. 17,5 kg).
  final bool decimal;

  /// Cuando es true el borde y el texto pasan a `danger`.
  final bool hasError;

  @override
  State<SetCellField> createState() => _SetCellFieldState();
}

class _SetCellFieldState extends State<SetCellField> {
  /// El nodo propio existe sólo cuando no viene uno de afuera. Se escucha para
  /// pintar el borde de foco: al pasar de `InputDecoration` a un `Container`
  /// —para que la celda se construya igual que el chip de SET— el
  /// `focusedBorder` dejó de existir, y sin él no se ve qué celda se está
  /// editando.
  FocusNode? _propio;

  FocusNode get _foco => widget.focusNode ?? (_propio ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _foco.addListener(_alCambiarFoco);
  }

  @override
  void didUpdateWidget(SetCellField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode?.removeListener(_alCambiarFoco);
      _foco.addListener(_alCambiarFoco);
    }
  }

  void _alCambiarFoco() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_alCambiarFoco);
    _propio
      ?..removeListener(_alCambiarFoco)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final tinta = widget.hasError ? palette.danger : palette.textPrimary;
    final enfocado = _foco.hasFocus;
    final colorBorde = widget.hasError
        ? palette.danger
        : enfocado
            ? palette.accent
            : palette.border;

    // MISMA construcción que `SetTypeChip`, no valores que casualmente
    // coinciden: un `Container` con `BoxDecoration` y las mismas
    // `constraints`. Antes la celda se dibujaba con `InputDecoration` +
    // `OutlineInputBorder` y el chip con un `Container`, dos caminos que
    // llegaban a alturas iguales en test y se veían distintos en el device —
    // el chip sólido, los campos hundidos. Revisión del 31/08.
    return Container(
      constraints: const BoxConstraints(minWidth: 44, minHeight: 48),
      decoration: BoxDecoration(
        color: palette.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: colorBorde,
          width: widget.hasError || enfocado ? 1.5 : 1.0,
        ),
      ),
      // Center con factores en 1 por el mismo motivo que el chip: `alignment`
      // mete un Align, y un Align con constraints acotadas se estira a
      // llenarlas.
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: TextField(
          controller: widget.controller,
          focusNode: _foco,
          keyboardType: widget.decimal
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.number,
          inputFormatters: [
            // QA-WKT-003: tope de dominio compartido, para que no se pueda
            // autorear un set imposible y que ese set fluya sin tocar hasta un
            // SetLog.
            BoundedNumberFormatter(
              max: widget.decimal ? kMaxWeightKg : kMaxReps.toDouble(),
              decimal: widget.decimal,
            ),
          ],
          style: GoogleFonts.barlow(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: tinta,
          ),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            isDense: true,
            // El borde y el relleno los pone el Container de afuera: acá
            // cualquier decoración volvería a meter una segunda caja.
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            // Padding vertical CERO: el alto lo pone el `minHeight` del
            // Container de afuera, igual que en el chip. Sumarle padding acá
            // llevaba la celda a 52 y volvía a desalinearla del chip, que es
            // justo lo que este cambio vino a arreglar.
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.hairline,
            ),
            hintText: widget.hint,
            hintStyle: GoogleFonts.barlow(
              fontSize: 13,
              color: widget.hasError
                  ? palette.danger.withAlpha(180)
                  : palette.textMuted,
            ),
          ),
          onChanged: (value) {
            if (widget.decimal) {
              widget.onDecimalChanged!(parseEditorWeight(value));
            } else {
              widget.onChanged!(int.tryParse(value));
            }
          },
        ),
      ),
    );
  }
}
