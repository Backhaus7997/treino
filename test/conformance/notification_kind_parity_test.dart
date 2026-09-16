// notification_kind_parity_test.dart — el enum de kinds, escrito dos veces.
//
// ─── Por qué existe ─────────────────────────────────────────────────────────
//
// `NotificationKind` vive en DOS lenguajes:
//
//   • TypeScript — `functions/src/notifications/send-fcm.ts`. Es la FUENTE DE
//     VERDAD: el backend elige el `kind`, lo manda por FCM y lo persiste en
//     `users/{uid}/notifications`.
//   • Dart — `lib/features/notifications/domain/notification_history_item.dart`.
//     Espejo a mano, que sólo lee lo que el backend escribió.
//
// Dos listas a mano en dos lenguajes divergen. No es una posibilidad, es
// cuestión de cuándo — el mismo razonamiento de `conformance/README.md`, sólo
// que acá el contrato es una ENUMERACIÓN, no una función que ejercitar.
//
// Y ya divergieron: `discomfort` y `monthly-report` estuvieron meses del lado
// TypeScript y no del lado Dart. Nadie se enteró, y ese es exactamente el
// problema. Hoy nada de la UI ramifica por el kind, así que un valor que falta
// cae en `NotificationKind.unknown` por el `orElse` de `fromJson` y la pantalla
// se dibuja igual: la deriva no tiene síntoma. El día que una pantalla empiece
// a ramificar —un ícono, un color, una acción por tipo— el mismo dato silencioso
// pasa a ser un bug de producto, y para entonces la lista va a estar mucho más
// lejos de lo que está hoy.
//
// ─── Por qué lee el `.ts` y no una lista escrita acá ────────────────────────
//
// Porque una lista escrita a mano en este archivo sería un TERCER espejo, y se
// desincronizaría por el mismo motivo que los otros dos. Un guard que hay que
// acordarse de actualizar no es un guard: es otro lugar donde olvidarse.
//
// Dart no puede importar un tipo de TypeScript, así que la única forma de leer
// la fuente de verdad de verdad es leer el archivo. Es la misma decisión —y por
// el mismo motivo— que `paywall_flag_parity_test.dart` toma para el Swift del
// reloj: feo, y lo único que de veras cierra el agujero.
//
// ─── La única exención, y por qué está declarada ────────────────────────────
//
// `NotificationKind.unknown` no tiene contraparte en TypeScript, a propósito:
// es el centinela del `orElse`, no un kind que el backend emita. Es la ÚNICA
// exención, está nombrada abajo en una constante, y tiene su propio test —
// porque una exención que sobrevive a su motivo es un agujero con permiso.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/notifications/domain/notification_history_item.dart';

/// El único valor del enum Dart al que **no** se le exige contraparte en TS.
///
/// No es "un valor que el TS todavía no tiene": es el centinela al que
/// `NotificationKind.fromJson` manda todo lo que no reconoce. Que el backend
/// nunca lo emita es parte del contrato, y lo fija el último test de este
/// archivo.
const NotificationKind _centinelaSoloDeDart = NotificationKind.unknown;

/// Los literales de `export type NotificationKind` en el archivo TypeScript.
///
/// Devuelve `null` si el bloque no está donde este test lo busca, o si está
/// pero no se le pudo sacar ni un literal. Las dos cosas significan lo mismo —
/// el guard quedó ciego— y las dos hacen fallar el test **a propósito**: un
/// guard que no encuentra lo que busca y pasa igual es peor que no tenerlo,
/// porque hace creer que hay una red que no está.
Set<String>? _kindsDelTypeScript(String fuente) {
  final bloque = RegExp(
    r'export\s+type\s+NotificationKind\s*=([^;]*);',
  ).firstMatch(fuente);
  if (bloque == null) return null;

  final literales = RegExp(r'"([^"]+)"')
      .allMatches(bloque.group(1)!)
      .map((m) => m.group(1)!)
      .toSet();
  return literales.isEmpty ? null : literales;
}

void main() {
  final ts = File('functions/src/notifications/send-fcm.ts');

  group('NotificationKind: Dart y TypeScript declaran lo mismo', () {
    test('el archivo TypeScript existe donde este test lo busca', () {
      expect(
        ts.existsSync(),
        isTrue,
        reason: 'no encontré ${ts.path} desde ${Directory.current}. '
            'Si se movió, movete este test con él en vez de borrarlo: sin '
            'esto, las dos listas vuelven a poder divergir en silencio.',
      );
    });

    test('la unión se puede leer del TypeScript', () {
      // Si esto falla, el guard quedó ciego. Puede ser que alguien haya
      // renombrado el tipo, lo haya movido a otro archivo, o lo haya
      // convertido en enum/const object. Arreglá el regex o el archivo —
      // no borres el test.
      expect(
        _kindsDelTypeScript(ts.readAsStringSync()),
        isNotNull,
        reason: 'no pude leer `export type NotificationKind = "…" | "…";` en '
            '${ts.path}, o lo leí vacío. Un guard que no encuentra lo que '
            'busca y pasa igual es peor que no tenerlo.',
      );
    });

    test('EL TEST QUE IMPORTA: todo kind del backend lo entiende el Dart', () {
      final delTs = _kindsDelTypeScript(ts.readAsStringSync())!;

      // Esto NO compara listas: ejercita `fromJson`, que es lo que de verdad
      // corre en producción cuando llega una notificación. Un kind que el
      // backend emite y el enum no tiene aterriza en el centinela, que es
      // exactamente el modo de falla silenciosa que este archivo existe para
      // convertir en rojo.
      final caenEnElCentinela = delTs
          .where(
              (kind) => NotificationKind.fromJson(kind) == _centinelaSoloDeDart)
          .toList()
        ..sort();

      expect(
        caenEnElCentinela,
        isEmpty,
        reason: 'El backend emite kinds que el enum Dart no declara:\n'
            '  ${caenEnElCentinela.join(', ')}\n\n'
            '`NotificationKind.fromJson` los manda a '
            '${_centinelaSoloDeDart.name} por el `orElse`, así que la app los '
            'muestra sin romperse y nadie se entera. Eso no es que funcione: '
            'es que la deriva no tiene síntoma.\n\n'
            'Agregalos a `NotificationKind` en '
            'lib/features/notifications/domain/notification_history_item.dart '
            'con el mismo literal que usa ${ts.path}.',
      );
    });

    test('y el Dart no declara kinds que el backend no emite', () {
      final delTs = _kindsDelTypeScript(ts.readAsStringSync())!;

      final soloEnDart = NotificationKind.values
          .where((kind) => kind != _centinelaSoloDeDart)
          .where((kind) => !delTs.contains(kind.value))
          .map((kind) => "${kind.name} ('${kind.value}')")
          .toList()
        ..sort();

      expect(
        soloEnDart,
        isEmpty,
        reason: 'El enum Dart declara kinds que ${ts.path} ya no emite:\n'
            '  ${soloEnDart.join(', ')}\n\n'
            'O se los sacaron al backend sin sacarlos acá —y entonces son '
            'ramas muertas que igual invitan a escribir UI para ellas—, o se '
            'agregaron acá primero y falta agregarlos allá.\n\n'
            'La exención de este test es UNA SOLA: '
            '${_centinelaSoloDeDart.name}, el centinela del `orElse`. '
            'No la ensanches para tapar este rojo.',
      );
    });

    test('la exención sigue teniendo motivo: el TS no emite el centinela', () {
      final delTs = _kindsDelTypeScript(ts.readAsStringSync())!;

      // Mismo criterio que la allowlist de `fixture_coverage_test.dart`: el
      // guard también falla cuando una exención sobrevive a su motivo.
      //
      // Si el backend empieza a emitir "unknown" como kind real, el centinela
      // deja de ser un valor imposible y pasa a colisionar con un dato
      // legítimo: `fromJson` no podría distinguir "el backend dijo unknown" de
      // "no reconocí lo que dijo el backend". Ahí hay que cambiar el diseño,
      // no la lista.
      expect(
        delTs.contains(_centinelaSoloDeDart.value),
        isFalse,
        reason: '${ts.path} ahora declara '
            "'${_centinelaSoloDeDart.value}' como kind emitible.\n\n"
            'Ese literal estaba reservado para el centinela de '
            '`NotificationKind.fromJson`. Con el backend emitiéndolo, el enum '
            'ya no puede distinguir un kind desconocido de uno que el backend '
            'llamó así a propósito.\n\n'
            'Esto se arregla en el diseño (otro literal para el centinela, o '
            'que el backend no use ese nombre), no ensanchando la exención.',
      );
    });
  });
}
