import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/paywall/domain/athlete_entitlement.dart';
import 'package:treino/features/paywall/domain/catalog_gate.dart';

/// Corre los fixtures compartidos de `conformance/catalog_gate.json` contra la
/// implementación Dart de [catalogGateBlocks].
///
/// El cliente watchOS reimplementa esta misma regla en Swift —no puede usar el
/// SDK de Firestore— y corre los MISMOS fixtures desde
/// `conformance/run_swift.sh`. Si divergen, el mismo alumno entrena una
/// plantilla en un reloj y le queda bloqueada en el otro. Ver
/// `conformance/README.md`.
void main() {
  group('conformance — catalog_gate.json', () {
    late Map<String, dynamic> fixture;

    setUpAll(() {
      final file = File('conformance/catalog_gate.json');
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
      expect(fixture['rule'], 'catalog-gate');
      expect(
        fixture['source_of_truth'],
        'lib/features/paywall/domain/catalog_gate.dart',
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

    test('el contrato cubre los TRES estados de paywallEnforced', () {
      // Sin este guard, un fixture que sólo probara `true` y `false` pasaría
      // feliz mientras el caso que de verdad importa —`null`, o sea "no se
      // sabe"— queda sin cubrir en las dos implementaciones. Y ése es el
      // estado de HOY: la CF todavía no escribe el campo en ningún lado.
      final valores = (fixture['cases'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((c) => (c['given'] as Map<String, dynamic>)['paywallEnforced'])
          .toSet();
      expect(
        valores,
        containsAll(<Object?>[true, false, null]),
        reason: 'El tri-estado es la razón por la que este contrato existe: '
            'las dos plataformas llegan a "no se sabe" por caminos distintos '
            '(AthleteEntitlement.unknown en Dart, el campo ausente en Swift) y '
            'las dos tienen que fallar ABIERTO.',
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

        final actual = catalogGateBlocks(
          paywallEnabled: given['paywallEnabled'] as bool,
          paywallEnforced: given['paywallEnforced'] as bool?,
          isPremium: given['isPremium'] as bool?,
        );
        final expectedBlocked = expected['blocked'] as bool;

        if (actual != expectedBlocked) {
          failures.add(
            '  · "$name"\n'
            '      esperado: $expectedBlocked\n'
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
            'Si el contrato es el correcto, arreglá catalog_gate.dart. Si el '
            'contrato está mal, corregí conformance/catalog_gate.json PRIMERO '
            'y después las dos implementaciones — nunca al revés.',
      );
    });
  });

  group('el puente desde AthleteEntitlement', () {
    // El enum es lo que el teléfono y el Wear resuelven; el fixture habla en
    // tri-estado. Si este mapeo se rompe, las dos implementaciones cumplen el
    // contrato cada una por su lado y el teléfono igual decide distinto.
    test('los tres estados mapean uno a uno', () {
      expect(AthleteEntitlement.entitled.paywallEnforced, isFalse);
      expect(AthleteEntitlement.free.paywallEnforced, isTrue);
      expect(AthleteEntitlement.unknown.paywallEnforced, isNull);
    });

    test('el mapeo coincide con gatesFreeLimits en los tres', () {
      // `gatesFreeLimits` es la puerta que usaban los call sites antes de que
      // existiera la función pura, y varios la siguen usando. Las dos formas
      // de preguntar lo mismo tienen que dar lo mismo, o el refactor movió el
      // comportamiento sin que nadie lo note.
      for (final e in AthleteEntitlement.values) {
        expect(
          e.paywallEnforced == true,
          e.gatesFreeLimits,
          reason: '$e: paywallEnforced y gatesFreeLimits discrepan',
        );
      }
    });
  });
}
