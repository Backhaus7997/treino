import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/notificaciones_prefs.dart';

/// Guard cruzado Dart ↔ TypeScript para el canal `push` de la matriz de
/// Notificaciones del Coach Hub.
///
/// POR QUÉ EXISTE
///
/// `kPushBackedTypes` afirma cuáles filas de la matriz tienen el toggle de push
/// realmente cableado contra `sendFcm`. Esa afirmación vive en Dart y la verdad
/// vive en `functions/src/notifications/`: dos lenguajes, dos suites, cero
/// forma de que una desincronización se note.
///
/// Y una afirmación así, sin nada que la verifique, es exactamente el problema
/// de AGENTS.md §11.1 — un cartel tranquilizador que miente desactiva la
/// sospecha justo donde hacía falta. El caso concreto que este guard previene:
/// alguien agrega una fila a `kNotifTypes` y la suma a `kPushBackedTypes` sin
/// cablear el `prefKey` en el productor. El PF ve una casilla, la destilda, y
/// el push le sigue llegando — que es el bug que este cambio vino a arreglar.
///
/// El corolario del §11.1 pide un comando reproducible al lado de toda
/// afirmación de completitud. Éste es el equivalente ejecutable de:
///
/// ```bash
/// rg -o 'prefKey[:= ]+"([a-z_]+)"' -r '$1' functions/src/notifications/*.ts | sort -u
/// ```
///
/// QUÉ MIRA
///
/// El `prefKey` que llega a `sendFcm`, y sólo ése. En los productores conviven
/// dos canales con el mismo nombre de campo: `enqueueMail` también recibe un
/// `prefKey` (para el canal email) y no tiene por qué coincidir — hoy no
/// coincide, email cubre 2 filas y push las 5. Por eso el scanner acota la
/// búsqueda al texto de la llamada `sendFcm(...)`, más las asignaciones a la
/// variable `prefKey` que esa llamada consume en los productores con varias
/// ramas (`notify-link-change`, `notify-appointment`).
void main() {
  /// Raíz del repo, derivada del cwd de `flutter test` (siempre la raíz del
  /// paquete). Si algún día se corre desde otro lado, el test falla ruidoso en
  /// vez de pasar en vacío por no encontrar archivos.
  final productoresDir = Directory('functions/src/notifications');

  /// Extrae el texto de cada llamada `sendFcm(` balanceando paréntesis.
  ///
  /// Un regex sobre líneas no alcanza: la llamada ocupa ~10 líneas y adentro
  /// hay objetos anidados. Balancear es corto y no se rompe si el formato
  /// cambia.
  List<String> bloquesSendFcm(String fuente) {
    final bloques = <String>[];
    var desde = 0;
    while (true) {
      final inicio = fuente.indexOf('sendFcm(', desde);
      if (inicio == -1) break;
      var i = fuente.indexOf('(', inicio);
      var nivel = 0;
      for (; i < fuente.length; i++) {
        if (fuente[i] == '(') nivel++;
        if (fuente[i] == ')') {
          nivel--;
          if (nivel == 0) break;
        }
      }
      bloques.add(fuente.substring(inicio, i));
      desde = i;
    }
    return bloques;
  }

  final literal = RegExp(r'''prefKey\s*:\s*["']([a-z_]+)["']''');
  final asignacion = RegExp(r'''prefKey\s*=\s*["']([a-z_]+)["']''');

  test('kPushBackedTypes coincide con los prefKey que recibe sendFcm', () {
    expect(
      productoresDir.existsSync(),
      isTrue,
      reason: 'No se encontró ${productoresDir.path} — ¿cambió el cwd del test?',
    );

    final encontrados = <String>{};
    var archivosLeidos = 0;

    for (final entrada in productoresDir.listSync()) {
      if (entrada is! File || !entrada.path.endsWith('.ts')) continue;
      archivosLeidos++;
      final fuente = entrada.readAsStringSync();

      // (a) `prefKey: "x"` escrito adentro del input de sendFcm.
      for (final bloque in bloquesSendFcm(fuente)) {
        for (final m in literal.allMatches(bloque)) {
          encontrados.add(m.group(1)!);
        }
      }
      // (b) `prefKey = "x"` — la variable que las ramas asignan y la llamada
      //     consume como `prefKey,`. Ese patrón es exclusivo del lado push:
      //     `enqueueMail` siempre recibe el suyo inline.
      for (final m in asignacion.allMatches(fuente)) {
        encontrados.add(m.group(1)!);
      }
    }

    expect(
      archivosLeidos,
      greaterThan(0),
      reason: 'El scanner no leyó ningún .ts — el resultado no significa nada.',
    );

    expect(
      encontrados,
      equals(kPushBackedTypes),
      reason: 'kPushBackedTypes dice una cosa y los productores hacen otra. '
          'Si cableaste un prefKey nuevo, sumalo a la constante; si sacaste '
          'uno, sacala. Una fila listada acá sin productor detrás es una '
          'casilla que el PF destilda y no hace nada.',
    );
  });

  test('toda fila con push cableado existe en kNotifTypes', () {
    final filas = {for (final t in kNotifTypes) t.key};
    expect(
      kPushBackedTypes.difference(filas),
      isEmpty,
      reason: 'Hay un prefKey cableado que no corresponde a ninguna fila de la '
          'matriz: el PF no tiene dónde apagarlo.',
    );
  });
}
