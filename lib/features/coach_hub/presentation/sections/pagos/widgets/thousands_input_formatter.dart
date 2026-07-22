/// `TextInputFormatter` de separador de miles es-AR para TextField de monto
/// (ARS) — puramente cosmético: el valor guardado sigue siendo un `int`
/// plano, sólo cambia el texto en pantalla mientras el coach tipea.
///
/// Sección: coach_hub/pagos — contrato: sin Scaffold, sin HEX, es-AR + // i18n.
library;

import 'package:flutter/services.dart';

import 'payment_format.dart' show groupThousands;

/// Formatea en vivo lo que el usuario tipea en un TextField de monto ARS,
/// agrupando de a 3 dígitos con "." (10000 → "10.000") — sin signo ni "$".
///
/// El caret siempre queda al final del texto formateado; no intenta
/// preservar la posición relativa del cursor (aceptable para este caso de
/// uso: monto corto, se tipea de una).
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    digits = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');

    if (digits.isEmpty) return TextEditingValue.empty;

    final formatted = groupThousands(digits);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Parsea el texto agrupado de un TextField de monto ARS a `int` plano
/// (quita los "." de agrupamiento antes de parsear). `null` si no es un
/// número válido — mismo contrato que `int.tryParse`.
int? parseGroupedInt(String text) =>
    int.tryParse(text.replaceAll('.', '').trim());
