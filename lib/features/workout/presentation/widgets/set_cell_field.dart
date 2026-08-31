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
class SetCellField extends StatelessWidget {
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

  /// Focus node externo — el campo de KG tiene uno propio para que su fila
  /// sepa cuándo mostrar los atajos.
  final FocusNode? focusNode;

  /// Callback entero, usado cuando [decimal] es false (reps, etc.).
  final void Function(int?)? onChanged;

  /// Callback double, usado cuando [decimal] es true (peso en kg).
  final void Function(double?)? onDecimalChanged;

  /// Cuando es true el campo acepta fraccionarios (ej. 17,5 kg).
  final bool decimal;

  /// Cuando es true el borde y el texto pasan a `danger`.
  final bool hasError;

  OutlineInputBorder _border(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) {
    final restingColor = hasError ? palette.danger : palette.border;
    final restingWidth = hasError ? 1.5 : 1.0;
    final focusedColor = hasError ? palette.danger : palette.accent;

    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: decimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.number,
      inputFormatters: [
        // QA-WKT-003: tope de dominio compartido, para que no se pueda autorear
        // un set imposible y que ese set fluya sin tocar hasta un SetLog.
        BoundedNumberFormatter(
          max: decimal ? kMaxWeightKg : kMaxReps.toDouble(),
          decimal: decimal,
        ),
      ],
      style: GoogleFonts.barlow(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: hasError ? palette.danger : palette.textPrimary,
      ),
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        isDense: true,
        // El piso de 48 va en el decorador y no en un ConstrainedBox de
        // afuera: el decorador se mide por su contenido y respeta este mínimo,
        // así que con Dynamic Type grande CRECE en vez de recortar el valor.
        // Un ConstrainedBox con minHeight suelto hace lo contrario — el campo
        // se estira a llenar todo el alto que le ofrezcan.
        constraints: const BoxConstraints(minHeight: 48),
        hintText: hint,
        hintStyle: GoogleFonts.barlow(
          fontSize: 13,
          color: hasError ? palette.danger.withAlpha(180) : palette.textMuted,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.hairline,
        ),
        filled: true,
        // `surfaceSubtle`, el mismo relleno que el chip de SET de la misma
        // fila. Con `bgCard` las tres celdas de una fila se leían como dos
        // familias distintas: el chip sólido y los campos hundidos. Revisión
        // en device del 31/08.
        fillColor: palette.surfaceSubtle,
        border: _border(restingColor, restingWidth),
        enabledBorder: _border(restingColor, restingWidth),
        focusedBorder: _border(focusedColor, 1.5),
      ),
      onChanged: (value) {
        if (decimal) {
          onDecimalChanged!(parseEditorWeight(value));
        } else {
          onChanged!(int.tryParse(value));
        }
      },
    );
  }
}
