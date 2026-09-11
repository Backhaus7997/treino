import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guard estructural del mecanismo de conformidad.
///
/// ## Qué agujero cierra
///
/// El runner Swift (`conformance/swift/main.swift`) invoca cada fixture **a
/// mano**, una línea por archivo, al final del `main`. No hay descubrimiento
/// automático. O sea que agregar un `conformance/*.json` y olvidarse de
/// cablearlo ahí deja el contrato **unilateral y en silencio**: el lado Dart lo
/// corre, el Swift ni lo mira, y CI queda verde.
///
/// Eso es peor que no tener el fixture. `conformance/README.md` explica que
/// estos archivos existen porque *"las mismas reglas escritas dos veces van a
/// divergir. No es una posibilidad, es cuestión de cuándo"* — un fixture que
/// sólo corre de un lado no protege de nada y encima hace creer que sí.
///
/// Es el mismo modo de falla que el propio README ya nombra para otro caso
/// (*"un fixture vacío pasaría en falso: es el modo de falla más peligroso de
/// este mecanismo"*), con otra forma.
///
/// ## Por qué hay una allowlist en vez de exigir siempre
///
/// Porque el orden correcto de trabajo pone el fixture PRIMERO —regla de oro
/// del README: *"se corrige el fixture primero y recién después las dos
/// implementaciones"*— así que existe una ventana legítima en la que el
/// contrato está escrito y una de las dos implementaciones todavía no.
///
/// La allowlist es esa ventana, hecha explícita. La diferencia con no tener
/// guard es que acá la deuda se declara, se explica y se ve en el diff: nadie
/// la contrae sin querer.
const Map<String, String> _pendientesDeSwift = {
  'catalog_gate.json':
      'La implementación Swift del gate del catálogo pago no existe todavía. '
          'El contrato está escrito y el lado Dart lo cumple '
          '(catalog_gate_conformance_test.dart); falta el reloj de Apple, y el '
          'plan completo está en docs/paywall-watchos-plan.md. Cuando se '
          'implemente: cablear runCatalogGate(...) en conformance/swift/'
          'main.swift y SACAR esta entrada — el guard empieza a exigirlo solo.',
};

void main() {
  group('cobertura de fixtures de conformidad', () {
    late List<String> fixtures;
    late String runnerSwift;

    setUpAll(() {
      final dir = Directory('conformance');
      expect(
        dir.existsSync(),
        isTrue,
        reason: 'No se encontró conformance/. Si el directorio se movió, '
            'movete este guard con él en vez de borrarlo.',
      );
      fixtures = dir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.json'))
          .toList()
        ..sort();

      final runner = File('conformance/swift/main.swift');
      expect(
        runner.existsSync(),
        isTrue,
        reason: 'No se encontró ${runner.path}, que es la mitad Swift del '
            'contrato. Sin él, ningún fixture se verifica cross-plataforma.',
      );
      runnerSwift = runner.readAsStringSync();
    });

    test('hay fixtures: un directorio vacío pasaría en falso', () {
      expect(fixtures, isNotEmpty);
    });

    test('cada fixture está invocado en el runner Swift', () {
      final huerfanos = <String>[];
      for (final nombre in fixtures) {
        if (_pendientesDeSwift.containsKey(nombre)) continue;
        // Se busca el nombre del archivo tal cual: el runner lo arma con
        // `conformanceDir.appendingPathComponent("<nombre>.json")`.
        if (!runnerSwift.contains('"$nombre"')) {
          huerfanos.add(nombre);
        }
      }

      expect(
        huerfanos,
        isEmpty,
        reason: 'Estos fixtures no los corre nadie del lado Swift, así que el '
            'contrato que prometen es unilateral:\n'
            '${huerfanos.map((h) => '  · $h').join('\n')}\n\n'
            'Cableá su runner en conformance/swift/main.swift. Si la '
            'implementación Swift todavía no existe, declaralo en '
            '`_pendientesDeSwift` de este archivo con el motivo — la deuda '
            'consciente se documenta, no se esconde.',
      );
    });

    test('la allowlist no tiene entradas muertas', () {
      // Una entrada que ya no corresponde es una advertencia falsa: hace creer
      // que falta trabajo que en realidad está hecho, o peor, silencia un
      // fixture que sí debería exigirse. AGENTS.md §11.1.
      final muertas = <String>[];
      for (final nombre in _pendientesDeSwift.keys) {
        if (!fixtures.contains(nombre)) {
          muertas.add('$nombre — el fixture ya no existe');
        } else if (runnerSwift.contains('"$nombre"')) {
          muertas.add('$nombre — el runner Swift YA lo corre');
        }
      }

      expect(
        muertas,
        isEmpty,
        reason: 'La allowlist tiene entradas que ya no corresponden:\n'
            '${muertas.map((m) => '  · $m').join('\n')}\n\n'
            'Sacalas. Una excepción que sobrevive a su motivo deja de ser una '
            'excepción y pasa a ser un agujero.',
      );
    });

    test('cada pendiente explica por qué lo está', () {
      for (final entry in _pendientesDeSwift.entries) {
        expect(
          entry.value.length,
          greaterThan(40),
          reason: '${entry.key} está en la allowlist con un motivo demasiado '
              'corto para ser útil. El que lo lea dentro de seis meses tiene '
              'que poder saber qué falta y cómo saldar la deuda.',
        );
      }
    });
  });
}
