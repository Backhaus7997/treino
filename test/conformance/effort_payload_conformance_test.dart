import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/watch/domain/watch_effort.dart';

/// Corre los fixtures compartidos de `conformance/effort_payload.json` contra
/// la implementación Dart de [WatchEffort.tryParse].
///
/// Este contrato es **asimétrico**: el que ESCRIBE el payload es Swift
/// (`EffortSnapshot.context(measuredAt:)`), el que lo LEE es Dart. Por eso el
/// fixture trae el diccionario exacto que tiene que viajar, y cada lado
/// verifica su mitad — Swift que lo produce igual, Dart que lo interpreta igual.
///
/// Existe porque el payload se autodeclaraba contrato y no tenía ninguno: las
/// claves estaban afirmadas dos veces contra literales escritos a mano, uno de
/// cada lado. Ver `conformance/README.md`.
void main() {
  group('conformance — effort_payload.json', () {
    late Map<String, dynamic> fixture;

    setUpAll(() {
      final file = File('conformance/effort_payload.json');
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
        'lib/features/watch/domain/watch_effort.dart',
      );
    });

    test('todos los casos del fixture', () {
      final cases = fixture['cases'] as List<dynamic>;
      expect(cases, isNotEmpty);

      for (final raw in cases) {
        final c = raw as Map<String, dynamic>;
        final name = c['name'] as String;
        final given = c['given'] as Map<String, dynamic>;
        final payload = c['expect'] as Map<String, dynamic>;

        final effort = WatchEffort.tryParse(payload);
        expect(effort, isNotNull, reason: 'caso "$name"');

        expect(effort!.bpm, given['bpm'], reason: 'bpm — caso "$name"');
        expect(effort.kcal, given['kcal'], reason: 'kcal — caso "$name"');
        expect(
          effort.measuredAt,
          DateTime.fromMillisecondsSinceEpoch(
            given['measuredAtMs'] as int,
            isUtc: true,
          ),
          reason: 'medido en — caso "$name"',
        );

        final timer = given['timer'] as Map<String, dynamic>?;
        if (timer == null) {
          expect(effort.timerEndsAt, isNull,
              reason: 'sin cronómetro — caso "$name"');
          expect(effort.timerExerciseId, isNull);
          expect(effort.timerSetNumber, isNull);
          expect(effort.timerTotalSeconds, isNull);
          continue;
        }

        expect(effort.timerExerciseId, timer['exerciseId'],
            reason: 'ejercicio del cronómetro — caso "$name"');
        expect(effort.timerSetNumber, timer['setNumber'],
            reason: 'serie del cronómetro — caso "$name"');
        expect(effort.timerTotalSeconds, timer['totalSeconds'],
            reason: 'segundos totales — caso "$name"');
        expect(
          effort.timerEndsAt,
          DateTime.fromMillisecondsSinceEpoch(
            timer['endsAtMs'] as int,
            isUtc: true,
          ),
          reason: 'instante de fin — caso "$name"',
        );
        expect(
          effort.timerCorreEn(
            exerciseId: timer['exerciseId'] as String,
            setNumber: timer['setNumber'] as int,
          ),
          isTrue,
          reason: 'la cuenta se ubica en su serie — caso "$name"',
        );
      }
    });

    test('los timestamps del fixture NO entran en 32 bits', () {
      // Misma presión que en `duration_timer.json`, y por el mismo motivo: en
      // watchOS `Int` es de 32 bits, escribir estos ms como `Int` TRAPEA
      // (commit 3a0840cc) y leerlos como `Int` devuelve nil en silencio. Si
      // alguien "simplificara" los casos a números chicos, esa presión
      // desaparecería sin que nada se pusiera rojo.
      const maxInt32 = 2147483647;
      for (final raw in fixture['cases'] as List<dynamic>) {
        final c = raw as Map<String, dynamic>;
        final given = c['given'] as Map<String, dynamic>;
        expect(given['measuredAtMs'] as int, greaterThan(maxInt32),
            reason: 'caso "${c['name']}"');
        final timer = given['timer'] as Map<String, dynamic>?;
        if (timer != null) {
          expect(timer['endsAtMs'] as int, greaterThan(maxInt32),
              reason: 'caso "${c['name']}"');
        }
      }
    });
  });
}
