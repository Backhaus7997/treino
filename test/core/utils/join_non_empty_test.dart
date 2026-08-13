// Tests de joinNonEmpty (#550) — el helper que evita separadores colgando
// (" · Otro", " · DÍA 1") cuando un segmento de una línea compuesta resuelve
// vacío (grupo muscular sin mapear, rutina sin split, etc.).

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/join_non_empty.dart';

void main() {
  group('joinNonEmpty (#550)', () {
    test('descarta segmentos vacíos antes de unir — sin separador colgando',
        () {
      // El caso exacto del bug de home: ['', 'Otro', ...].join(' · ')
      // devolvía " · Otro · ..." — acá el vacío se filtra primero.
      expect(
        joinNonEmpty(['', 'Otro', 'Abdominales'], ' · '),
        'Otro · Abdominales',
      );
    });

    test('descarta null y segmentos whitespace-only', () {
      expect(joinNonEmpty([null, '   ', 'DÍA 1'], ' · '), 'DÍA 1');
    });

    test('todos los segmentos vacíos → cadena vacía', () {
      expect(joinNonEmpty(['', null, '   '], ' · '), '');
    });

    test('lista vacía → cadena vacía', () {
      expect(joinNonEmpty(const <String>[], ' · '), '');
    });

    test('sin segmentos vacíos → equivalente a join', () {
      expect(joinNonEmpty(['PPL', 'DÍA 1'], ' · '), 'PPL · DÍA 1');
    });

    test('vacíos intercalados no duplican el separador', () {
      expect(joinNonEmpty(['A', '', 'B', null, 'C'], ' · '), 'A · B · C');
    });

    test('segmentos retenidos NO se trimean — el filtro no formatea', () {
      expect(joinNonEmpty([' A ', 'B'], '·'), ' A ·B');
    });
  });
}
