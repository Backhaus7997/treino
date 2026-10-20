import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/widgets/treino_toast.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../core/utils/kg_format.dart';

/// A [TextInputFormatter] that keeps a numeric field's text inside a domain
/// ceiling, rejecting any keystroke that would push the value over [max] or
/// introduce a second decimal separator.
///
/// This fixes the display-vs-persisted divergence (QA-WKT-002): with a reactive
/// "clamp then rewrite the controller" approach the field fights the user while
/// they type a decimal (`1.` briefly fails to parse); rejecting the offending
/// keystroke at the source means the text the athlete sees is always exactly
/// the value that gets parsed and logged. It also enforces the shared caps on
/// the editor so an impossible set can't be authored (QA-WKT-003).
///
/// For integer fields pass [decimal] `false`: only digits are allowed. For
/// weight pass [decimal] `true`: a single `.` or `,` separator is allowed.
class BoundedNumberFormatter extends TextInputFormatter {
  const BoundedNumberFormatter({
    required this.max,
    required this.decimal,
    this.onOverMax,
  });

  /// Inclusive upper bound the parsed value may reach.
  final double max;

  /// Whether a single decimal separator (`.` or `,`) is permitted.
  final bool decimal;

  /// Se llama cuando una tecla se rechaza POR PASARSE de [max] — no por un
  /// carácter inválido ni por un separador de más. Sin aviso, recortar en
  /// silencio hacía que «9999,5» quedara en «99» sin que el atleta se
  /// enterara (#1510). Ver [avisarTopeAlcanzado].
  final VoidCallback? onOverMax;

  TextEditingValue _rechazarPorTope(TextEditingValue oldValue) {
    onOverMax?.call();
    return oldValue;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    // An empty field is a valid intermediate state (means "0" / unset).
    if (text.isEmpty) return newValue;

    if (!decimal) {
      if (!RegExp(r'^[0-9]+$').hasMatch(text)) return oldValue;
      final value = int.tryParse(text);
      if (value != null && value > max) return _rechazarPorTope(oldValue);
      return newValue;
    }

    // Weight: accept comma as separator (iOS numeric keypad) but only one.
    final normalized = text.replaceAll(',', '.');
    if ('.'.allMatches(normalized).length > 1) return oldValue;
    if (!RegExp(r'^[0-9]*\.?[0-9]*$').hasMatch(normalized)) return oldValue;
    final value = double.tryParse(normalized);
    if (value != null && value > max) return _rechazarPorTope(oldValue);
    return newValue;
  }
}

/// Feedback de una tecla rechazada por el tope: háptico + «Máximo 500 kg».
///
/// Es un SnackBar y no un texto bajo la celda porque las dos celdas que usan
/// el formatter tienen alto fijo: un helper text desbordaría. Reemplaza al
/// anterior en vez de encolarse, así tipear varias teclas de más no apila
/// avisos.
void avisarTopeAlcanzado(BuildContext context,
    {required double max, required String unit}) {
  HapticFeedback.selectionClick();
  if (ScaffoldMessenger.maybeOf(context) == null) return;
  final valor = formatWeightKg(max).replaceAll('.', ',');
  showTreinoToast(context, AppL10n.of(context).inputMaxReached(valor, unit));
}
