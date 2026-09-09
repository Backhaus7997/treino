import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Todo `SnackBar` CON acción tiene que declarar `persist` explícitamente.
///
/// Por qué existe este candado, y por qué un `duration` no alcanza:
///
/// ```dart
/// // packages/flutter/lib/src/material/snack_bar.dart
/// persist = persist ?? action != null;
/// ```
///
/// Un cartel con acción es **eterno por default**, y `ScaffoldMessenger` ni
/// siquiera le agenda el timer de cierre (`if (snackBar.persist) return;`, en
/// `scaffold.dart`). Peor: el `duration` que le pongas al lado **no se mira**.
/// Tres carteles de esta app declaraban una duración que no hacía nada.
///
/// El PF lo reportó como «llega esta notificación y no desaparece hasta que
/// recargo la página».
///
/// El candado NO obliga a `false`: obliga a ELEGIR. Un cartel que de verdad
/// tenga que quedarse pone `persist: true` y queda dicho en el código.
void main() {
  test('todo SnackBar con acción declara `persist`', () {
    final ofensores = <String>[];

    for (final entidad in Directory('lib').listSync(recursive: true)) {
      if (entidad is! File || !entidad.path.endsWith('.dart')) continue;
      final lineas = entidad.readAsLinesSync();

      for (var i = 0; i < lineas.length; i++) {
        if (!lineas[i].contains('action: SnackBarAction')) continue;

        // Hacia atrás hasta la apertura del `SnackBar(` que lo contiene.
        var apertura = -1;
        for (var j = i; j >= 0 && i - j < 40; j--) {
          if (lineas[j].contains('SnackBar(')) {
            apertura = j;
            break;
          }
        }
        if (apertura < 0) continue;

        final cuerpo = lineas.sublist(apertura, i).join('\n');
        if (!cuerpo.contains('persist:')) {
          ofensores.add('${entidad.path}:${i + 1}');
        }
      }
    }

    expect(
      ofensores,
      isEmpty,
      reason: 'Estos SnackBar tienen acción y no dicen si persisten, así que '
          'son ETERNOS por default y su `duration` —si lo tienen— se ignora:\n'
          '  ${ofensores.join('\n  ')}',
    );
  });
}
