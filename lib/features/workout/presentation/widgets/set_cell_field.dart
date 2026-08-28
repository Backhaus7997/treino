import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/tokens.dart';
import '../../domain/set_limits.dart';
import 'bounded_number_formatter.dart';

double? parseEditorWeight(String value) =>
    double.tryParse(value.replaceAll(',', '.'));

/// Boxed numeric field used by the routine editor's set table.
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
  final FocusNode? focusNode;
  final void Function(int?)? onChanged;
  final void Function(double?)? onDecimalChanged;
  final bool decimal;
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

    return SizedBox(
      height: 48,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: decimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.number,
        inputFormatters: [
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
          hintText: hint,
          hintStyle: GoogleFonts.barlow(
            fontSize: 13,
            color: hasError ? palette.danger.withAlpha(180) : palette.textMuted,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.hairline,
          ),
          filled: true,
          fillColor: palette.bgCard,
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
      ),
    );
  }
}
