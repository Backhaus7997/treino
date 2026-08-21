import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/superset_order.dart';

/// Corre los fixtures compartidos de `conformance/superset_order.json` contra
/// la implementación Dart de [SupersetOrder].
///
/// El contrato existe porque el orden de una superserie es lo que la DEFINE.
/// El teléfono recorría vuelta por vuelta y el reloj ejercicio por ejercicio, y
/// las dos producían datos válidos: misma identidad lógica de serie, mismos
/// documentos. Nada se ponía en rojo. Lo único que cambiaba era el ORDEN en que
/// el atleta hacía el trabajo — o sea, el entrenamiento. Ver `conformance/README.md`.
void main() {
  group('conformance — superset_order.json', () {
    late Map<String, dynamic> fixture;

    setUpAll(() {
      final file = File('conformance/superset_order.json');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'No se encontró ${file.path}. Los fixtures de conformidad son '
            'el contrato con la implementación Swift: si el archivo no está, '
            'ese contrato no existe.',
      );
      fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    });

    test('el fixture apunta a la implementación que este test ejercita', () {
      expect(
        fixture['source_of_truth'],
        'lib/features/workout/domain/superset_order.dart',
      );
    });

    test('todos los casos del fixture', () {
      final cases = fixture['cases'] as List<dynamic>;
      expect(cases, isNotEmpty);

      for (final raw in cases) {
        final c = raw as Map<String, dynamic>;
        final name = c['name'] as String;
        final given = c['given'] as Map<String, dynamic>;
        final expected = c['expect'] as Map<String, dynamic>;

        final members = [
          for (final m in given['members'] as List<dynamic>)
            (
              exerciseId: (m as Map<String, dynamic>)['exerciseId'] as String,
              plannedSets: m['plannedSets'] as int,
              loggedSets: m['loggedSets'] as int,
            ),
        ];

        expect(
          SupersetOrder.totalRounds(members),
          expected['totalRounds'],
          reason: 'vueltas totales — caso "$name"',
        );

        final cell = SupersetOrder.nextCell(members);
        if (expected['exerciseId'] == null) {
          expect(cell, isNull, reason: 'bloque completo — caso "$name"');
          continue;
        }
        expect(cell, isNotNull, reason: 'caso "$name"');
        expect(cell!.exerciseId, expected['exerciseId'],
            reason: 'ejercicio — caso "$name"');
        expect(cell.setNumber, expected['setNumber'],
            reason: 'serie — caso "$name"');
        expect(cell.round, expected['round'], reason: 'vuelta — caso "$name"');
      }
    });
  });
}
