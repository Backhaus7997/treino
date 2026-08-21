import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/duration_timer.dart';

/// Corre los fixtures compartidos de `conformance/duration_timer.json` contra
/// la implementación Dart de [DurationTimerRules].
///
/// El contrato existe porque la cuenta regresiva estaba escrita dos veces: el
/// reloj contra el reloj de pared, el teléfono por ticks. Las dos daban el
/// mismo número mientras nada las molestara — y por eso la divergencia era
/// invisible hasta que el sistema estrangulaba la app y una plancha de 60
/// segundos duraba 70. Ver `conformance/README.md`.
void main() {
  group('conformance — duration_timer.json', () {
    late Map<String, dynamic> fixture;

    setUpAll(() {
      final file = File('conformance/duration_timer.json');
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
        'lib/features/workout/domain/duration_timer.dart',
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

        final endsAt = DateTime.fromMillisecondsSinceEpoch(
          given['endsAtMs'] as int,
          isUtc: true,
        );
        final now = DateTime.fromMillisecondsSinceEpoch(
          given['nowMs'] as int,
          isUtc: true,
        );

        expect(
          DurationTimerRules.remaining(endsAt: endsAt, now: now),
          expected['remaining'],
          reason: 'segundos restantes — caso "$name"',
        );
        expect(
          DurationTimerRules.isFinished(endsAt: endsAt, now: now),
          expected['finished'],
          reason: 'terminada — caso "$name"',
        );
      }
    });

    test('los timestamps del fixture NO entran en 32 bits', () {
      // El fixture presiona a propósito sobre la trampa que crasheó el reloj
      // (commit 3a0840cc): en watchOS `Int` es de 32 bits. Si alguien
      // "simplificara" los casos a offsets chicos, esa presión desaparecería
      // sin que nada se pusiera rojo — y el contrato dejaría de proteger lo
      // que dice proteger en su campo `inputs.note`.
      const maxInt32 = 2147483647;
      for (final raw in fixture['cases'] as List<dynamic>) {
        final given =
            (raw as Map<String, dynamic>)['given'] as Map<String, dynamic>;
        expect(
          given['endsAtMs'] as int,
          greaterThan(maxInt32),
          reason: 'caso "${raw['name']}": el fixture tiene que usar epoch '
              'absoluto en ms, no offsets',
        );
        expect(given['nowMs'] as int, greaterThan(maxInt32));
      }
    });
  });
}
