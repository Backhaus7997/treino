import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';

/// Corre los fixtures compartidos de `conformance/session_counting.json` contra
/// la implementación Dart de [sessionCountsAsWorkout].
///
/// Este contrato existe porque `plan_advance.json` cubría la DECISIÓN pero no
/// QUÉ SE LE PASA: el reloj filtraba las sesiones por `finishedAt` presente y
/// el teléfono por `status == finished && wasFullyCompleted`. Los dos avanzaban
/// el plan desde sesiones distintas, y `plan_advance.json` siguió en verde todo
/// ese tiempo. Ver `conformance/README.md`.
void main() {
  group('conformance — session_counting.json', () {
    late Map<String, dynamic> fixture;

    setUpAll(() {
      final file = File('conformance/session_counting.json');
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
      expect(fixture['rule'], 'session-counting');
      expect(
        fixture['source_of_truth'],
        'lib/features/workout/domain/session.dart',
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

      // Se acumulan TODAS las discrepancias antes de fallar: con un solo
      // `expect` por caso, la primera esconde las demás.
      final failures = <String>[];

      for (final testCase in cases) {
        final name = testCase['name'] as String;
        final given = testCase['given'] as Map<String, dynamic>;
        final expected = testCase['expect'] as Map<String, dynamic>;

        // `status` y `wasFullyCompleted` pueden ser null a propósito: campo
        // ausente o nulo explícito son entradas legítimas del contrato, y son
        // justo las que el reloj ve al leer el JSON crudo de la REST API.
        final actual = sessionCountsAsWorkout(
          status: given['status'] as String?,
          wasFullyCompleted: given['wasFullyCompleted'] as bool?,
        );

        final expectedValue = expected['countsAsWorkout'] as bool;

        if (actual != expectedValue) {
          failures.add(
            '  · "$name"\n'
            '      esperado: $expectedValue\n'
            '      obtenido: $actual',
          );
        }
      }

      expect(
        failures,
        isEmpty,
        reason: 'La implementación Dart discrepa del contrato compartido en '
            '${failures.length} de ${cases.length} casos:\n'
            '${failures.join('\n')}\n\n'
            'Si el contrato es el correcto, arreglá session.dart. Si el '
            'contrato está mal, corregí conformance/session_counting.json '
            'PRIMERO y después las dos implementaciones — nunca al revés.',
      );
    });

    // El contrato se define sobre los valores de wire, pero la app usa el
    // getter `Session.countsAsWorkout`. Si el getter dejara de delegar en la
    // función contrastada, el contrato quedaría verde mientras la app hace otra
    // cosa — que es exactamente el modo de falla que este fixture vino a
    // cerrar, una capa más arriba.
    test('el getter de Session concuerda con la función bajo contrato', () {
      Session build({required SessionStatus status, required bool full}) =>
          Session(
            id: 's1',
            uid: 'u1',
            routineId: 'r1',
            routineName: 'Rutina',
            startedAt: DateTime.utc(2026, 1, 1),
            status: status,
            wasFullyCompleted: full,
          );

      for (final status in SessionStatus.values) {
        for (final full in [true, false]) {
          final session = build(status: status, full: full);
          expect(
            session.countsAsWorkout,
            sessionCountsAsWorkout(
              status: status.toJson(),
              wasFullyCompleted: full,
            ),
            reason: 'El getter y la función contrastada difieren para '
                'status=${status.toJson()}, wasFullyCompleted=$full.',
          );
        }
      }
    });

    // `wasFullyCompleted` ausente en el documento tiene que dar false, igual
    // que en Swift. Del lado Dart eso lo resuelve `@Default(false)` al
    // deserializar, así que se ejercita el camino real: `Session.fromJson`.
    test('un documento sin wasFullyCompleted no cuenta', () {
      final session = Session.fromJson({
        'id': 's1',
        'uid': 'u1',
        'routineId': 'r1',
        'routineName': 'Rutina',
        // `@TimestampConverter()` espera el tipo de Firestore, no un ISO
        // string: el documento llega tal cual del SDK, sin pasar por JSON.
        'startedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
        'status': 'finished',
      });

      expect(
        session.wasFullyCompleted,
        isFalse,
        reason: 'El @Default(false) del modelo es lo que hace que Swift pueda '
            'leer nil y dar el mismo resultado. Si esto cambiara a true, todo '
            'el historial legacy pasaría a contar de golpe.',
      );
      expect(session.countsAsWorkout, isFalse);
    });
  });
}
