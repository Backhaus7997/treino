import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ratchet (#1560): `SnackBar(` crudo fuera de `showTreinoToast`.
///
/// POR QUÉ. Cada pantalla armaba su `SnackBar` a mano (con o sin ícono, con
/// colores propios), y el de un bottom sheet quedaba tapado (#1490). El
/// estilo vive en `AppTheme.snackBarTheme` y el contenido en
/// `lib/core/widgets/treino_toast.dart`.
///
/// LA REGLA. El conteo de construcciones `SnackBar(` en `lib/` (menos el
/// helper) sólo BAJA. Migrar un archivo a `showTreinoToast` => bajá
/// [baseline] en el mismo commit. Subirlo está prohibido: usá el helper.
///
/// QUÉ **NO** PRUEBA. Que el toast se vea bien; sólo que no se agregan
/// SnackBars nuevos a mano.
const int baseline = 203;

const _helper = 'lib/core/widgets/treino_toast.dart';

/// `(?<![A-Za-z.])` descarta `showSnackBar(`, `hideCurrentSnackBar(`,
/// `ScaffoldMessenger.of(..).SnackBar(`-style y `FooSnackBar(`.
final _patron = RegExp(r'(?<![A-Za-z.])SnackBar\(');

void main() {
  test('el conteo de SnackBar( crudos no supera el baseline', () {
    final porArchivo = <String, int>{};
    var total = 0;

    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final ruta = e.path.replaceAll(r'\', '/');
      if (ruta.endsWith(_helper)) continue;
      final n =
          _patron.allMatches(_sinComentarios(e.readAsStringSync())).length;
      if (n == 0) continue;
      porArchivo[ruta] = n;
      total += n;
    }

    expect(
      total,
      lessThanOrEqualTo(baseline),
      reason: 'Hay $total SnackBar( crudos (baseline $baseline). Usá '
          'showTreinoToast(context, msg, type: …) de '
          'lib/core/widgets/treino_toast.dart.',
    );
    // Ratchet: si bajó, obligá a bajar el número (si no, el hueco se
    // reabsorbe en silencio con un SnackBar nuevo).
    expect(
      total,
      baseline,
      reason: 'El conteo bajó a $total: actualizá `baseline` en este test '
          'para que no se pueda volver a subir.\n'
          '${(porArchivo.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(10).map((e) => '${e.value}  ${e.key}').join('\n')}',
    );
  });
}

String _sinComentarios(String src) => src.split('\n').map((l) {
      final i = l.indexOf('//');
      if (i == -1) return l;
      final antes = l.substring(0, i);
      final comillas =
          "'".allMatches(antes).length + '"'.allMatches(antes).length;
      return comillas.isEven ? antes : l;
    }).join('\n');
