import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// La pantalla del código NO puede hablar de pagos.
//
// El mail que lleva el código explica que los pagos y sus confirmaciones van
// por mail y trae un botón a los planes. Eso se puede decir AFUERA de la app.
// Adentro, un «revisá el mail para pagar» es un llamado a comprar fuera de la
// tienda, y con eso se cae la exención 3.1.3(f) — la misma doctrina que
// `test/features/paywall/superficie_de_cobro_alumno_test.dart` vigila para la
// hoja de tope. Esta pantalla vive en `features/auth` y aquel test no la mira:
// por eso tiene la suya.
//
// Se escanea el código SIN comentarios (los comentarios explican justamente lo
// que la pantalla no dice) y en minúsculas.

const _archivo = 'lib/features/auth/presentation/verify_mail_screen.dart';

const _prohibidas = <String>[
  'pago',
  'pagar',
  'plan',
  'suscrip',
  'precio',
  'cobr',
  'web',
  'checkout',
  'mercado',
];

String _sinComentarios(String fuente) => fuente
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((linea) {
      final i = linea.indexOf('//');
      return i >= 0 ? linea.substring(0, i) : linea;
    })
    .join('\n')
    .toLowerCase();

List<String> _encontradas(String fuente) {
  final texto = _sinComentarios(fuente);
  return _prohibidas.where(texto.contains).toList();
}

void main() {
  test('la pantalla del código no habla de pagos ni de dónde se paga', () {
    final fuente = File(_archivo).readAsStringSync();

    expect(_encontradas(fuente), isEmpty);
  });

  test('control: el escáner caza una palabra plantada', () {
    // Sin esto, un escáner roto (ruta mal, regex que se come todo) pasaría en
    // verde para siempre.
    const plantada = "Text('Mirá los planes en tu mail'),";
    expect(_encontradas(plantada), contains('plan'));
    // Y no confunde un comentario con texto de la pantalla.
    expect(_encontradas('// acá hablamos de pagos'), isEmpty);
  });
}
