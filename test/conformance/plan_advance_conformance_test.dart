import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/plan_advance.dart';

/// Corre los fixtures compartidos de `conformance/plan_advance.json` contra la
/// implementación Dart de [nextPlanPosition].
///
/// El cliente watchOS reimplementa esta misma regla en Swift y va a correr los
/// MISMOS fixtures. Ese es el punto: si una implementación cambia y la otra no,
/// CI se pone en rojo antes de que el historial del usuario se corrompa en
/// silencio. Ver `conformance/README.md`.
///
/// Ojo: mientras solo corra el lado Dart, esto fija el contrato pero todavía no
/// detecta divergencia — hace falta el corredor Swift para eso.
void main() {
  group('conformance — plan_advance.json', () {
    late Map<String, dynamic> fixture;

    setUpAll(() {
      // Los tests corren con el root del paquete como cwd.
      final file = File('conformance/plan_advance.json');
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
      expect(fixture['rule'], 'plan-advance');
      expect(
        fixture['source_of_truth'],
        'lib/features/workout/domain/plan_advance.dart',
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

      // Se acumulan TODAS las discrepancias antes de fallar. Con un solo
      // `expect` por caso, la primera divergencia esconde las demás — y cuando
      // Dart y Swift empiecen a separarse, querés ver el alcance completo.
      final failures = <String>[];

      for (final testCase in cases) {
        final name = testCase['name'] as String;
        final given = testCase['given'] as Map<String, dynamic>;
        final expected = testCase['expect'] as Map<String, dynamic>;

        final lastRaw = given['lastFinished'] as Map<String, dynamic>?;
        final actual = nextPlanPosition(
          lastFinished: lastRaw == null
              ? null
              : (
                  dayNumber: lastRaw['dayNumber'] as int,
                  weekNumber: lastRaw['weekNumber'] as int,
                ),
          numDays: given['numDays'] as int,
          numWeeks: given['numWeeks'] as int,
        );

        final expectedDay = expected['dayNumber'] as int;
        final expectedWeek = expected['weekNumber'] as int;

        if (actual.dayNumber != expectedDay ||
            actual.weekNumber != expectedWeek) {
          failures.add(
            '  · "$name"\n'
            '      esperado: día $expectedDay, semana $expectedWeek\n'
            '      obtenido: día ${actual.dayNumber}, semana ${actual.weekNumber}',
          );
        }
      }

      expect(
        failures,
        isEmpty,
        reason: 'La implementación Dart discrepa del contrato compartido en '
            '${failures.length} de ${cases.length} casos:\n'
            '${failures.join('\n')}\n\n'
            'Si el contrato es el correcto, arreglá plan_advance.dart. Si el '
            'contrato está mal, corregí conformance/plan_advance.json PRIMERO '
            'y después las dos implementaciones — nunca al revés.',
      );
    });
  });
}
