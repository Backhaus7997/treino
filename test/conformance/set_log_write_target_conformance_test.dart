import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/set_log_identity.dart';

/// Corre los fixtures compartidos de `conformance/set_log_write_target.json`
/// contra la implementación Dart de [resolveSetLogWriteTarget].
///
/// Es la regla que decide dónde escribe un RELOJ una serie. Vive dos veces —acá
/// y en `ios/TreinoWatch Watch App/SetLogIdentity.swift`— y una divergencia de
/// un carácter vuelve a duplicar documentos en silencio, que es lo que costó 24
/// documentos de más y 11.450 kg fantasma.
void main() {
  group('conformance — set_log_write_target.json', () {
    late Map<String, dynamic> fixture;

    setUpAll(() {
      final file = File('conformance/set_log_write_target.json');
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
      expect(fixture['rule'], 'set-log-write-target');
      expect(
        fixture['source_of_truth'],
        'lib/features/workout/domain/set_log_identity.dart',
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
      final failures = <String>[];

      for (final testCase in cases) {
        final name = testCase['name'] as String;
        final given = testCase['given'] as Map<String, dynamic>;
        final expected = testCase['expect'] as Map<String, dynamic>;

        final remote = [
          for (final raw in (given['remote'] as List<dynamic>)
              .cast<Map<String, dynamic>>())
            RemoteSetLogRef(
              docId: raw['docId'] as String,
              exerciseId: raw['exerciseId'] as String,
              setNumber: raw['setNumber'] as int,
            ),
        ];

        final actual = resolveSetLogWriteTarget(
          exerciseId: given['exerciseId'] as String,
          setNumber: given['setNumber'] as int,
          remote: remote,
        );

        final actualKind =
            actual is SetLogAlreadyThere ? 'alreadyThere' : 'write';
        final expectedKind = expected['kind'] as String;
        final expectedDocId = expected['docId'] as String;

        if (actualKind != expectedKind || actual.docId != expectedDocId) {
          failures.add(
            '  · "$name"\n'
            '      esperado: $expectedKind → $expectedDocId\n'
            '      obtenido: $actualKind → ${actual.docId}',
          );
        }
      }

      expect(
        failures,
        isEmpty,
        reason: 'La implementación Dart discrepa del contrato compartido en '
            '${failures.length} de ${cases.length} casos:\n'
            '${failures.join('\n')}\n\n'
            'Si el contrato es el correcto, arreglá set_log_identity.dart. Si '
            'el contrato está mal, corregí el JSON PRIMERO y después las dos '
            'implementaciones — nunca al revés.',
      );
    });
  });
}
