import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/exercise_cursor.dart';

/// Corre los fixtures compartidos de `conformance/exercise_cursor.json` contra
/// la implementación Dart de [firstUnfinishedExerciseIndex].
///
/// El cliente watchOS tiene la MISMA regla en Swift —`ExerciseCursor.swift`, de
/// donde ésta fue portada— y `conformance/run_swift.sh` corre estos mismos
/// casos contra aquella. Ese es el punto: si una implementación cambia y la
/// otra no, CI se pone en rojo antes de que el atleta encuentre la muñeca
/// clavada en un ejercicio ya terminado.
void main() {
  group('conformance — exercise_cursor.json', () {
    late Map<String, dynamic> fixture;

    setUpAll(() {
      // Los tests corren con el root del paquete como cwd.
      final file = File('conformance/exercise_cursor.json');
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
      expect(fixture['rule'], 'exercise-cursor');
      expect(
        fixture['source_of_truth'],
        'lib/features/workout/domain/exercise_cursor.dart',
      );
    });

    test('el fixture tiene casos: un archivo vacío pasaría en falso', () {
      final cases = fixture['cases'] as List<dynamic>;
      expect(
        cases,
        isNotEmpty,
        reason: 'Un fixture sin casos hace que la suite pase sin verificar '
            'nada — el modo de falla más peligroso de este mecanismo.',
      );
    });

    test('cada caso resuelve como dice el contrato', () {
      final cases =
          (fixture['cases'] as List<dynamic>).cast<Map<String, dynamic>>();

      // Se acumulan TODAS las discrepancias antes de fallar: con un `expect`
      // por caso, la primera esconde a las demás, y cuando Dart y Swift
      // empiecen a separarse querés ver el alcance completo.
      final failures = <String>[];

      for (final testCase in cases) {
        final name = testCase['name'] as String;
        final given = testCase['given'] as Map<String, dynamic>;
        final expected = testCase['expect'] as Map<String, dynamic>;

        final actual = firstUnfinishedExerciseIndex(
          plannedSets: (given['plannedSets'] as List<dynamic>).cast<int>(),
          loggedSets: (given['loggedSets'] as List<dynamic>).cast<int>(),
        );
        final expectedIndex = expected['index'] as int;

        if (actual != expectedIndex) {
          failures.add(
            '  · "$name"\n'
            '      planificadas: ${given['plannedSets']}\n'
            '      cargadas:     ${given['loggedSets']}\n'
            '      esperado: índice $expectedIndex\n'
            '      obtenido: índice $actual',
          );
        }
      }

      expect(
        failures,
        isEmpty,
        reason: 'La implementación Dart discrepa del contrato compartido en '
            '${failures.length} de ${cases.length} casos:\n'
            '${failures.join('\n')}\n\n'
            'Si el contrato es el correcto, arreglá exercise_cursor.dart. Si el '
            'contrato está mal, corregí conformance/exercise_cursor.json '
            'PRIMERO y después las dos implementaciones — nunca al revés.',
      );
    });
  });
}
