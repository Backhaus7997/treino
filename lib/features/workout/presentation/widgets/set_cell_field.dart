import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../domain/set_limits.dart';
import 'bounded_number_formatter.dart';
import 'set_cell_box.dart';

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

    return SetCellBox(
      focused: _foco.hasFocus,
      hasError: widget.hasError,
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
          color: widget.hasError ? palette.danger : palette.textPrimary,
        ),
        textAlign: TextAlign.center,
        decoration: setCellDecoration(
          palette: palette,
          hint: widget.hint,
          hasError: widget.hasError,
        ).copyWith(
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
    );
  }
}
