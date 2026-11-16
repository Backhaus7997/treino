import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #1694 — el recorte de avatar en la web.
///
/// `image_cropper_for_web` >= 5.0.0 (hoy 7.0.0) usa `@JS("Cropper")`, o sea
/// cropperjs 1.x. `web/index.html` cargaba croppie, que es de las versiones 4.x
/// del plugin: el global `Cropper` no existía y LISTO fallaba con «cropper has
/// not been initialized». Ningún PF podía cambiar su foto desde el Hub.
///
/// Esto es una guarda de configuración, no una prueba del recorte: que el
/// cropper ande de verdad se mira a mano, en un build web.
void main() {
  final raiz = Directory.current.path;

  const cropperJs = 'https://unpkg.com/cropperjs@1.6.2/dist/cropper.min.js';
  const cropperCss = 'https://unpkg.com/cropperjs@1.6.2/dist/cropper.min.css';

  /// El `index.html` SIN comentarios: el que explica el arreglo nombra croppie.
  String indexHtml() => File('$raiz/web/index.html')
      .readAsStringSync()
      .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

  List<String> atributo(String html, String tag, String attr) =>
      RegExp('<$tag\\b[^>]*\\b$attr="([^"]+)"')
          .allMatches(html)
          .map((m) => m.group(1)!)
          .toList();

  /// Las fuentes de una directiva (`script-src`, `style-src`) del CSP que
  /// publica `firebase.json`. Hoy es `Content-Security-Policy-Report-Only`:
  /// avisa, no bloquea. Igual es la lista que hay que respetar para el día que
  /// se promueva a enforced.
  List<String> fuentesDelCsp(String directiva) {
    final config = jsonDecode(File('$raiz/firebase.json').readAsStringSync())
        as Map<String, Object?>;
    for (final sitio in config['hosting']! as List) {
      final reglas = (sitio as Map)['headers'] as List? ?? const [];
      for (final regla in reglas) {
        for (final header in (regla as Map)['headers'] as List) {
          final h = header as Map;
          if (!(h['key'] as String).startsWith('Content-Security-Policy')) {
            continue;
          }
          for (final parte in (h['value'] as String).split(';')) {
            final tokens = parte.trim().split(RegExp(r'\s+'));
            if (tokens.first == directiva) return tokens.skip(1).toList();
          }
        }
      }
    }
    fail('firebase.json no declara `$directiva` en ningún CSP');
  }

  test('index.html ya no carga croppie', () {
    expect(
      indexHtml().toLowerCase().contains('croppie'),
      isFalse,
      reason: 'croppie es la librería de las versiones 4.x de '
          'image_cropper_for_web; con la 7.0.0 no define el global `Cropper`',
    );
  });

  test('index.html carga cropperjs 1.6.2, la versión que documenta el plugin',
      () {
    final html = indexHtml();
    expect(atributo(html, 'script', 'src'), contains(cropperJs));
    expect(atributo(html, 'link', 'href'), contains(cropperCss));
  });

  test('los scripts y estilos externos salen de un host que el CSP permite',
      () {
    final html = indexHtml();
    final scripts = fuentesDelCsp('script-src');
    final estilos = fuentesDelCsp('style-src');

    final scriptsExternos = atributo(html, 'script', 'src')
        .where((u) => u.startsWith('https://'))
        .toList();
    final estilosExternos = atributo(html, 'link', 'href')
        .where((u) => u.startsWith('https://'))
        .toList();
    expect(scriptsExternos, isNotEmpty);
    expect(estilosExternos, isNotEmpty);

    for (final url in scriptsExternos) {
      expect(scripts, contains(Uri.parse(url).origin),
          reason: '$url no está en el script-src de firebase.json');
    }
    for (final url in estilosExternos) {
      expect(estilos, contains(Uri.parse(url).origin),
          reason: '$url no está en el style-src de firebase.json');
    }
  });
}
