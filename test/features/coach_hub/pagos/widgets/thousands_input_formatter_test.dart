/// Tests for ThousandsSeparatorInputFormatter + parseGroupedInt.
///
/// Verifica el separador de miles es-AR cosmético en TextField de monto
/// (ARS) y que el parseo de vuelta a `int` plano sea correcto — el trap a
/// evitar es que "10.000" formateado rompa `int.tryParse` al guardar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/thousands_input_formatter.dart';

void main() {
  group('ThousandsSeparatorInputFormatter', () {
    final formatter = ThousandsSeparatorInputFormatter();

    TextEditingValue format(String text) => formatter.formatEditUpdate(
          TextEditingValue.empty,
          TextEditingValue(text: text),
        );

    test('"10000" -> "10.000"', () {
      expect(format('10000').text, '10.000');
    });

    test('"1000000" -> "1.000.000"', () {
      expect(format('1000000').text, '1.000.000');
    });

    test('"500" -> "500" (sin separador, menos de 4 dígitos)', () {
      expect(format('500').text, '500');
    });

    test('empty input -> empty text', () {
      expect(format('').text, '');
    });

    test('caret siempre al final del texto formateado', () {
      final result = format('10000');
      expect(result.selection.baseOffset, result.text.length);
    });
  });

  group('parseGroupedInt', () {
    test('"10.000" -> 10000', () {
      expect(parseGroupedInt('10.000'), 10000);
    });

    test('"" -> null', () {
      expect(parseGroupedInt(''), isNull);
    });

    test('"abc" -> null', () {
      expect(parseGroupedInt('abc'), isNull);
    });
  });
}
