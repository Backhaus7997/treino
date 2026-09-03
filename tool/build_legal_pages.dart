// Genera las páginas legales públicas de `web/legal/` a partir de
// `legal_content.dart`.
//
// ─── Por qué generadas y no escritas a mano ──────────────────────────────────
//
// Las dos tiendas piden una URL PÚBLICA de la política de privacidad, y el
// texto ya existe adentro de la app (`kPrivacySections`). Escribir el HTML a
// mano sería tener el mismo documento legal en dos lugares — y este repo ya
// sabe cómo termina eso: el "Quick reference" de `CLAUDE.md` duplicaba las
// reglas de `AGENTS.md` y se desincronizó hasta dejar a dos agentes con
// constituciones distintas. Con un texto legal el costo no es un agente
// confundido: es que la política que aceptó el usuario en la app diga una cosa
// y la que declaraste en la tienda diga otra.
//
// La fuente de verdad es y sigue siendo `legal_content.dart`. Esto es un
// renderer.
//
// ─── Uso ─────────────────────────────────────────────────────────────────────
//
//     dart run tool/build_legal_pages.dart
//
// Reescribe `web/legal/*.html` y `web/legal/_estilo.css`. Los archivos
// generados SE COMMITEAN: Firebase Hosting sirve `build/web/`, y `flutter build
// web` copia `web/` adentro — así que las páginas viajan con el build del Coach
// Hub sin necesidad de un target de hosting propio.
//
// Si editás el Dart y te olvidás de correr esto, te lo avisa
// `test/legal/paginas_legales_sync_test.dart` en vez de que se entere un
// usuario.

import 'dart:io';

import 'package:treino/features/auth/presentation/legal/legal_content.dart';

/// Paleta de marca. Duplica los valores de `AppColorPrimitives` a propósito:
/// esto corre en la VM de Dart pelada y `Color` vive en `dart:ui`, que no está
/// disponible fuera de Flutter. Que no derive lo fija el test de sincronismo,
/// que sí corre en Flutter y puede comparar contra los primitivos reales.
const _tokens = <String, String>{
  '--ink': '#0A0A0A',
  '--card': '#0F1513',
  '--mint': '#2CE5A2',
  '--bone': '#FFFFFF',
  '--muted': '#9BA8A1',
  '--line': '#1E2724',
};

const _bannerGenerado = '''
<!--
  ⚠️ ARCHIVO GENERADO — NO LO EDITES A MANO.

  Sale de `tool/build_legal_pages.dart`, que lee el texto de
  `lib/features/auth/presentation/legal/legal_content.dart`. Editar acá te deja
  la política de la tienda diciendo una cosa y la que el usuario aceptó en la
  app diciendo otra.

  Para cambiar el texto: editá el Dart y corré
      dart run tool/build_legal_pages.dart
-->''';

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// Convierte el cuerpo de una sección en párrafos. Los saltos de línea dobles
/// del Dart separan párrafos; los simples son sólo wrapping del código fuente y
/// no significan nada.
String _cuerpo(String body) {
  final parrafos = body
      .split(RegExp(r'\n\s*\n'))
      .map((p) => p.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((p) => p.isNotEmpty);
  return parrafos.map((p) => '    <p>${_escape(p)}</p>').join('\n');
}

String _pagina({
  required String titulo,
  required String subtitulo,
  required List<LegalSection> secciones,
  required String ultimaActualizacion,
}) {
  final cuerpo = secciones
      .map((s) => '''
  <section>
    <h2>${_escape(s.heading)}</h2>
${_cuerpo(s.body)}
  </section>''')
      .join('\n\n');

  return '''<!doctype html>
<html lang="es-AR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="dark">
<title>${_escape(titulo)} · TREINO</title>
<link rel="stylesheet" href="/legal/_estilo.css">
$_bannerGenerado
</head>
<body>
<main>
  <div class="brand">
    <a href="https://gettreino.com"><img src="/email/wordmark.png" alt="TREINO" width="110" height="56"></a>
  </div>

  <h1>${_escape(titulo)}</h1>
  <p class="lede">${_escape(subtitulo)}</p>

$cuerpo

  <footer>
    Última actualización: ${_escape(ultimaActualizacion)}.<br>
    Consultas: <a href="mailto:${_escape(kLegalContactEmail)}">${_escape(kLegalContactEmail)}</a><br>
    <a href="/legal/terminos.html">Términos y Condiciones</a> ·
    <a href="/legal/privacidad.html">Política de Privacidad</a> ·
    <a href="/legal/eliminar-cuenta.html">Eliminar tu cuenta</a>
  </footer>
</main>
</body>
</html>
''';
}

const _css = r'''
/*
 * ⚠️ GENERADO por tool/build_legal_pages.dart — no lo edites a mano.
 *
 * Mismo criterio que /abrir/_estilo.css: una hoja compartida en vez de un
 * bloque inline por página, porque tres documentos con el mismo diseño y tres
 * copias del CSS son tres oportunidades de que uno quede con el mint viejo.
 *
 * A diferencia de /abrir, estas páginas son de LECTURA LARGA: la medida de
 * línea se acota en ~68ch y el interlineado sube. Un documento legal que no se
 * puede leer es un documento legal que nadie lee.
 */
:root {
__TOKENS__
}

* { box-sizing: border-box; }

body {
  margin: 0;
  background: var(--ink);
  color: var(--bone);
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
               Helvetica, Arial, sans-serif;
  -webkit-font-smoothing: antialiased;
  display: flex;
  justify-content: center;
  padding: 40px 20px 72px;
  min-height: 100vh;
}

main { width: 100%; max-width: 68ch; }

.brand { margin-bottom: 32px; }
.brand img { display: block; height: 40px; width: auto; }

h1 {
  margin: 0 0 12px;
  font-size: 30px;
  line-height: 1.15;
  letter-spacing: -0.5px;
}

.lede {
  margin: 0 0 8px;
  color: var(--muted);
  font-size: 16px;
  line-height: 1.6;
}

section {
  border-top: 1px solid var(--line);
  margin-top: 28px;
  padding-top: 22px;
}

h2 {
  margin: 0 0 12px;
  font-size: 18px;
  line-height: 1.3;
  color: var(--mint);
}

p {
  margin: 0 0 14px;
  color: var(--muted);
  line-height: 1.75;
  font-size: 15px;
}

strong { color: var(--bone); font-weight: 600; }

a { color: var(--mint); }

footer {
  border-top: 1px solid var(--line);
  margin-top: 36px;
  padding-top: 20px;
  font-size: 13px;
  line-height: 1.8;
  color: var(--muted);
}
footer a { color: var(--muted); }
''';

void main() {
  final dir = Directory('web/legal');
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final tokens =
      _tokens.entries.map((e) => '  ${e.key}: ${e.value};').join('\n');
  File('web/legal/_estilo.css')
      .writeAsStringSync(_css.replaceFirst('__TOKENS__', tokens));

  File('web/legal/privacidad.html').writeAsStringSync(_pagina(
    titulo: 'Política de Privacidad',
    subtitulo:
        'Qué datos tuyos guarda TREINO, para qué, y qué podés hacer con ellos.',
    secciones: kPrivacySections,
    ultimaActualizacion: kPrivacyLastUpdated,
  ));

  File('web/legal/terminos.html').writeAsStringSync(_pagina(
    titulo: 'Términos y Condiciones',
    subtitulo: 'Las reglas de uso de TREINO. En castellano y sin letra chica.',
    secciones: kTermsSections,
    ultimaActualizacion: kTermsLastUpdated,
  ));

  stdout.writeln('Generado:');
  stdout.writeln('  web/legal/_estilo.css');
  stdout.writeln(
      '  web/legal/privacidad.html  (${kPrivacySections.length} secciones)');
  stdout
      .writeln('  web/legal/terminos.html    (${kTermsSections.length} secciones)');
  stdout.writeln('');
  stdout.writeln('web/legal/eliminar-cuenta.html NO se genera: no sale del');
  stdout.writeln('Dart, se edita a mano.');
}
