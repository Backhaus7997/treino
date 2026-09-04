import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/routine_selection.dart';

/// Corre los fixtures compartidos de `conformance/routine_selection.json`
/// contra la implementación Dart de [resolveActiveRoutineId].
///
/// El cliente watchOS reimplementa esta misma regla en Swift y corre los MISMOS
/// fixtures desde `conformance/run_swift.sh`. Si divergen, teléfono y reloj le
/// muestran rutinas DISTINTAS al mismo usuario. Ver `conformance/README.md`.
void main() {
  group('conformance — routine_selection.json', () {
    late Map<String, dynamic> fixture;

    setUpAll(() {
      final file = File('conformance/routine_selection.json');
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
      expect(fixture['rule'], 'routine-selection');
      expect(
        fixture['source_of_truth'],
        'lib/features/workout/domain/routine_selection.dart',
      );
    });

    test('el fixture tiene casos: un archivo vacío pasaría en falso', () {
      expect(
        fixture['cases'] as List<dynamic>,
        isNotEmpty,
        reason: 'Un fixture sin casos hace que la suite pase sin verificar '
            'nada — el modo de falla más peligroso de este mecanismo.',
      );
    });

    test('cada caso resuelve como dice el contrato', () {
      final cases =
          (fixture['cases'] as List<dynamic>).cast<Map<String, dynamic>>();

      // Se acumulan TODAS las discrepancias antes de fallar: con un solo
      // `expect` por caso, la primera esconde las demás.
      final failures = <String>[];

      for (final testCase in cases) {
        final name = testCase['name'] as String;
        final given = testCase['given'] as Map<String, dynamic>;
        final expected = testCase['expect'] as Map<String, dynamic>;

        final actual = resolveActiveRoutineId(
          activeRoutineId: given['activeRoutineId'] as String?,
          assignedIds: (given['assignedIds'] as List<dynamic>).cast<String>(),
          selfCreatedIds:
              (given['selfCreatedIds'] as List<dynamic>).cast<String>(),
          // Opcional en el fixture: los casos anteriores a "seguir sin copiar"
          // no lo traen, y ausente significa lista vacía. El runner Swift lee
          // este campo con el mismo default.
          catalogIds:
              (given['catalogIds'] as List<dynamic>?)?.cast<String>() ??
                  const [],
        );
        final expectedId = expected['routineId'] as String?;

        if (actual != expectedId) {
          failures.add(
            '  · "$name"\n'
            '      esperado: ${expectedId ?? "null"}\n'
            '      obtenido: ${actual ?? "null"}',
          );
        }
      }

      expect(
        failures,
        isEmpty,
        reason: 'La implementación Dart discrepa del contrato compartido en '
            '${failures.length} de ${cases.length} casos:\n'
            '${failures.join('\n')}\n\n'
            'Si el contrato es el correcto, arreglá routine_selection.dart. Si '
            'el contrato está mal, corregí conformance/routine_selection.json '
            'PRIMERO y después las dos implementaciones — nunca al revés.',
      );
    });
  });
}
