import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/set_log_identity.dart';

/// Corre los fixtures compartidos de `conformance/set_log_identity.json` contra
/// la implementación Dart de [setLogDeterministicDocId].
///
/// Este contrato existe porque el arreglo de los `setLogs` duplicados depende de
/// que el TELÉFONO busque la serie en la MISMA ruta donde el RELOJ la escribe.
/// La fórmula del id vive escrita dos veces, una por lenguaje: si divergen
/// aunque sea en el separador, el teléfono busca donde no está, no encuentra
/// nada, y vuelve a crear un segundo documento de la misma serie — en silencio,
/// sin que ningún otro test se ponga rojo. Ver `conformance/README.md`.
void main() {
  group('conformance — set_log_identity.json', () {
    late Map<String, dynamic> fixture;

    setUpAll(() {
      final file = File('conformance/set_log_identity.json');
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
      expect(fixture['rule'], 'set-log-identity');
      expect(
        fixture['source_of_truth'],
        'lib/features/workout/domain/set_log_identity.dart',
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

        final actual = setLogDeterministicDocId(
          exerciseId: given['exerciseId'] as String,
          setNumber: given['setNumber'] as int,
        );
        final expectedDocId = expected['docId'] as String;

        if (actual != expectedDocId) {
          failures.add(
            '  · "$name"\n'
            '      esperado: $expectedDocId\n'
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
            'Si el contrato es el correcto, arreglá set_log_identity.dart. Si '
            'el contrato está mal, corregí conformance/set_log_identity.json '
            'PRIMERO y después las dos implementaciones — nunca al revés.',
      );
    });

    // La identidad se decide por los CAMPOS del documento, nunca por su ruta.
    // Un documento puede quedar en una ruta que ya no lo describe: al borrar una
    // serie el teléfono renumera las sobrevivientes conservando el id, así que
    // `sentadilla__3` puede terminar conteniendo la serie 2. Escribir ahí
    // confiando en el path perdería un dato del atleta.
    test('un documento renumerado NO se toma por la serie de su ruta', () {
      expect(
        setLogDocHoldsSet(
          docExerciseId: 'sentadilla',
          docSetNumber: 2,
          exerciseId: 'sentadilla',
          setNumber: 3,
        ),
        isFalse,
        reason: 'El documento sentadilla__3 quedó con setNumber 2 tras una '
            'renumeración. Darlo por la serie 3 lo pisaría.',
      );
      expect(
        setLogDocHoldsSet(
          docExerciseId: 'sentadilla',
          docSetNumber: 3,
          exerciseId: 'sentadilla',
          setNumber: 3,
        ),
        isTrue,
      );
      expect(
        setLogDocHoldsSet(
          docExerciseId: 'prensa',
          docSetNumber: 3,
          exerciseId: 'sentadilla',
          setNumber: 3,
        ),
        isFalse,
      );
    });

    // Un documento sin los campos —o con tipos raros— no puede pasar por la
    // serie que se está por escribir. Es la lectura cruda de Firestore, así que
    // los tipos no están garantizados.
    test('un documento sin los campos no cuenta como la serie', () {
      expect(
        setLogDocHoldsSet(
          docExerciseId: null,
          docSetNumber: null,
          exerciseId: 'sentadilla',
          setNumber: 1,
        ),
        isFalse,
      );
      expect(
        setLogDocHoldsSet(
          docExerciseId: 'sentadilla',
          docSetNumber: '1',
          exerciseId: 'sentadilla',
          setNumber: 1,
        ),
        isFalse,
        reason: 'Un setNumber que llega como String no es el int del contrato: '
            'darlo por bueno abriría la puerta a pisar el documento equivocado.',
      );
    });
  });
}
