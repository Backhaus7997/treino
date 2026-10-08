// paywall_flag_parity_test.dart — el interruptor maestro, escrito dos veces.
//
// ─── Por qué existe ─────────────────────────────────────────────────────────
//
// `kAthletePaywallEnabled` vive en DOS lenguajes:
//
//   • Dart  — `lib/features/paywall/domain/athlete_entitlement.dart`, que sirve
//     al teléfono y al reloj Wear.
//   • Swift — `ios/TreinoWatch Watch App/PaywallEntitlement.swift`, el reloj de
//     Apple, que no puede importar nada de Dart.
//
// Dos constantes en dos lenguajes divergen. No es una posibilidad, es cuestión
// de cuándo — es exactamente el razonamiento de `conformance/README.md`, sólo
// que acá no hay una función que ejercitar: es un booleano.
//
// El día del encendido alguien va a tocar uno y puede olvidarse del otro. Si
// se prende el Dart y no el Swift, el reloj de Apple deja entrenar plantillas
// pagas que el teléfono bloquea. Si se prende el Swift y no el Dart, el atleta
// ve un candado en la muñeca que no existe en ningún otro lado.
//
// ─── Por qué un grep y no algo más elegante ─────────────────────────────────
//
// Porque no hay nada más elegante disponible: Dart no puede leer una constante
// de Swift, y el runner de conformidad ejercita FUNCIONES, no declaraciones.
// Un grep sobre el literal es feo y es lo único que de verdad cierra el
// agujero. Los guards de este repo ya usan esta forma —escanean `lib/` con
// agujas de texto— y funciona por el mismo motivo: convierte un olvido
// silencioso en una conversación.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/paywall/domain/athlete_entitlement.dart';

/// El literal de la constante en el archivo Swift del reloj.
///
/// Devuelve `null` si el archivo cambió de forma — y eso hace fallar el test a
/// propósito: un guard que no encuentra lo que busca y pasa igual es peor que
/// no tenerlo.
bool? _flagDelSwift(String fuente) {
  final m = RegExp(
    r'^let\s+kAthletePaywallEnabled\s*=\s*(true|false)\s*$',
    multiLine: true,
  ).firstMatch(fuente);
  if (m == null) return null;
  return m.group(1) == 'true';
}

void main() {
  group('kAthletePaywallEnabled: Dart y Swift dicen lo mismo', () {
    final swift = File('ios/TreinoWatch Watch App/PaywallEntitlement.swift');

    test('el archivo Swift existe donde este test lo busca', () {
      expect(
        swift.existsSync(),
        isTrue,
        reason: 'no encontré ${swift.path} desde ${Directory.current}. '
            'Si se movió, movete este test con él en vez de borrarlo: sin '
            'esto, las dos constantes pueden divergir en silencio.',
      );
    });

    test('la constante se puede leer del Swift', () {
      // Si esto falla, el guard quedó ciego. Puede ser que alguien la haya
      // renombrado, la haya hecho `var`, o la haya movido a otro archivo.
      expect(
        _flagDelSwift(swift.readAsStringSync()),
        isNotNull,
        reason: 'no pude leer `let kAthletePaywallEnabled = <bool>` en '
            '${swift.path}. Un guard que no encuentra lo que busca y pasa '
            'igual es peor que no tenerlo: arreglá el regex o el archivo.',
      );
    });

    test('EL TEST QUE IMPORTA: los dos valen lo mismo', () {
      final enSwift = _flagDelSwift(swift.readAsStringSync());

      expect(
        enSwift,
        kAthletePaywallEnabled,
        reason: 'El interruptor maestro del paywall del alumno NO coincide '
            'entre plataformas:\n'
            '  Dart  (teléfono y Wear): $kAthletePaywallEnabled\n'
            '  Swift (reloj de Apple):  $enSwift\n\n'
            'Con el Dart prendido y el Swift apagado, el reloj de Apple deja '
            'entrenar plantillas pagas que el teléfono bloquea.\n'
            'Al revés, el atleta ve un candado en la muñeca que no existe en '
            'ningún otro lado.\n\n'
            'El orden para encenderlo está en docs/paywall-watchos-plan.md §5, '
            'y no es arbitrario: PRIMERO el servidor, DESPUÉS el cliente.',
      );
    });
  });
}
