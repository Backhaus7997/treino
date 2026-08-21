import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

/// Corre los fixtures compartidos de `conformance/set_resolution.json` contra
/// el modelo REAL del teléfono (`RoutineSlot.effectiveSetsForWeek` /
/// `isActiveInWeek`), no contra una copia.
///
/// El reloj reimplementa esta misma regla en Swift y corre los MISMOS fixtures.
/// Es la lógica más sutil del dominio: define lo que el atleta efectivamente
/// levanta. Ver `conformance/README.md`.
void main() {
  group('conformance — set_resolution.json', () {
    late Map<String, dynamic> fixture;

    setUpAll(() {
      final file = File('conformance/set_resolution.json');
      expect(file.existsSync(), isTrue, reason: 'No se encontró ${file.path}.');
      fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    });

    test('el fixture apunta a la implementación que este test ejercita', () {
      expect(fixture['rule'], 'set-resolution');
    });

    test('el fixture tiene casos: un archivo vacío pasaría en falso', () {
      expect(fixture['cases'] as List<dynamic>, isNotEmpty);
    });

    test('cada caso resuelve como dice el contrato', () {
      final cases =
          (fixture['cases'] as List<dynamic>).cast<Map<String, dynamic>>();
      final failures = <String>[];

      for (final testCase in cases) {
        final name = testCase['name'] as String;
        final given = testCase['given'] as Map<String, dynamic>;
        final expected = testCase['expect'] as Map<String, dynamic>;

        final slot = RoutineSlot(
          exerciseId: 'ex',
          exerciseName: 'Ejercicio',
          muscleGroup: 'quads',
          targetSets: given['targetSets'] as int,
          durationSeconds: given['durationSeconds'] as int?,
          targetReps: (given['targetReps'] as List<dynamic>).cast<int>(),
          targetRepsMin: given['targetRepsMin'] as int,
          targetRepsMax: given['targetRepsMax'] as int,
          restSeconds: 90,
          targetWeightKg: (given['targetWeightKg'] as num?)?.toDouble(),
          sets: _specs(given['sets']),
          weeklySets: (given['weeklySets'] as List<dynamic>)
              .map((w) => _specs(w))
              .toList(growable: false),
          activeWeeks: (given['activeWeeks'] as List<dynamic>).cast<int>(),
        );

        final week = given['week'] as int;
        final actualActive = slot.isPresentInWeek(week);
        final expectedActive = expected['isActive'] as bool;
        if (actualActive != expectedActive) {
          failures.add(
            '  · "$name" (isActive)\n'
            '      esperado: $expectedActive\n'
            '      obtenido: $actualActive',
          );
        }

        final actualSets = slot
            .effectiveSetsForWeek(week)
            .map(_normalize)
            .toList(growable: false);
        final expectedSets = (expected['sets'] as List<dynamic>)
            .map((s) => _normalizeJson(s as Map<String, dynamic>))
            .toList(growable: false);

        if (actualSets.toString() != expectedSets.toString()) {
          failures.add(
            '  · "$name" (sets)\n'
            '      esperado: $expectedSets\n'
            '      obtenido: $actualSets',
          );
        }
      }

      expect(
        failures,
        isEmpty,
        reason: 'La implementación Dart discrepa del contrato compartido en '
            '${failures.length} comprobaciones:\n${failures.join('\n')}\n\n'
            'Si el contrato es el correcto, arreglá routine_slot.dart. Si el '
            'contrato está mal, corregí conformance/set_resolution.json '
            'PRIMERO y después las dos implementaciones — nunca al revés.',
      );
    });
  });
}

List<SetSpec> _specs(Object? raw) => (raw as List<dynamic>)
    .cast<Map<String, dynamic>>()
    .map(
      (s) => SetSpec(
        reps: s['reps'] as int?,
        repsMin: s['repsMin'] as int?,
        repsMax: s['repsMax'] as int?,
        weightKg: (s['weightKg'] as num?)?.toDouble(),
        durationSeconds: s['durationSeconds'] as int?,
      ),
    )
    .toList(growable: false);

/// Se comparan solo los campos que el contrato fija. `type` y demás quedan
/// fuera a propósito: el fixture describe QUÉ levanta el atleta, no la
/// representación interna de cada lenguaje.
String _normalize(SetSpec s) =>
    '{reps:${s.reps},min:${s.repsMin},max:${s.repsMax},'
    'kg:${s.weightKg},dur:${s.durationSeconds}}';

String _normalizeJson(Map<String, dynamic> s) =>
    '{reps:${s['reps']},min:${s['repsMin']},max:${s['repsMax']},'
    'kg:${(s['weightKg'] as num?)?.toDouble()},dur:${s['durationSeconds']}}';
