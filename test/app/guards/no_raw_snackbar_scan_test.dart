import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ratchet (#1560): `SnackBar(` crudo fuera de `showTreinoToast`.
///
/// POR QUÉ. Cada pantalla armaba su `SnackBar` a mano (con o sin ícono, con
/// colores propios), y el de un bottom sheet quedaba tapado (#1490). El
/// estilo y el contenido viven en `lib/core/widgets/treino_toast.dart`.
///
/// LA REGLA. El conteo de construcciones `SnackBar(` en `lib/` (menos el
/// helper) no supera [baseline]. Migrar un archivo a `showTreinoToast` =>
/// bajá [baseline] al conteo real en el mismo commit. Subirlo está
/// prohibido: usá el helper.
///
/// QUÉ **NO** PRUEBA. Que el toast se vea bien; sólo que no se agregan
/// SnackBars nuevos a mano.
const int baseline = 111;

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

    final peores = (porArchivo.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(10)
        .map((e) => '${e.value}  ${e.key}')
        .join('\n');
    // `<=` y no igualdad: el conteo baja en PRs paralelos que migran
    // pantallas, y una igualdad exacta pone rojo al primero que mergea.
    expect(
      total,
      lessThanOrEqualTo(baseline),
      reason: 'Hay $total SnackBar( crudos y el techo es $baseline. No '
          'agregues SnackBar a mano: usá showTreinoToast(context, msg, '
          'type: …) de lib/core/widgets/treino_toast.dart.\n'
          'Si migraste pantallas, bajá `baseline` en '
          'test/app/guards/no_raw_snackbar_scan_test.dart al conteo real '
          'para que el hueco no se reabsorba.\n$peores',
    );
  });
}

/// Saca comentarios `// …` y `/* … */` en UN solo pase junto con los
/// literales de string: así un `/*` dentro de un `//` (`lib/l10n/*.arb`) o de
/// un string no abre un bloque falso que se coma código real hasta el
/// próximo `*/`. Los strings se conservan tal cual.
String _sinComentarios(String src) => src.replaceAllMapped(
      _tokens,
      (m) => m[0]!.startsWith('/') ? '' : m[0]!,
    );

final _tokens = RegExp(
  r"""'(?:\\.|[^'\\\n])*'|"(?:\\.|[^"\\\n])*"|//[^\n]*|/\*[\s\S]*?\*/""",
);
