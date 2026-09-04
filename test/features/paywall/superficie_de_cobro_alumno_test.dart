// Guard de superficie de cobro — el lado del ALUMNO.
//
// ─── Qué regla protege ──────────────────────────────────────────────────────
//
// `docs/paywall-alumno-suelto.md` §7 elige la Guideline **3.1.3(f)** de Apple
// (*Free Stand-alone App*): la app móvil no vende nada **ni linkea al
// checkout**; el alumno paga en la web y el entitlement llega por Firestore.
//
// La segunda mitad de esa frase es la que se rompe sola. Que la app no cobre
// lo sostiene un tipo sellado (`PlanCheckoutOnWebOnly`) y lo fija el group
// «guard de superficie» de `pricing_screen_test.dart`. Pero **abrir el
// navegador hacia la pasarela no toca ese tipo**: es un `launchUrl` de una
// línea, en cualquier archivo, y compila.
//
// ─── Por qué este archivo existe, si ya hay un guard ────────────────────────
//
// El de `pricing_screen_test.dart` es estructural sobre UNA carpeta:
// `coach_hub/presentation/sections/facturacion_planes`. Es el paywall del
// ENTRENADOR.
//
// El del ALUMNO vive en `lib/features/paywall/` y no estaba cubierto por
// ninguno — y es justo donde va el trabajo nuevo: `free_plan_limit_sheet.dart`
// tiene un `onUpgrade` hoy `null`, con un dartdoc que dice textual "cuando el
// checkout exista, [onUpgrade] deja de ser null y la hoja dibuja el botón
// sola". Ese es el día en que alguien tiene que decidir qué hace el botón, y
// la respuesta correcta —no abrir nada— no la garantiza ningún tipo.
//
// ─── El costo de equivocarse ────────────────────────────────────────────────
//
// No es un warning: es rechazo de review, o la comisión de la tienda sobre
// cada suscripción. Y Argentina no está en el External Purchase Link
// Entitlement, así que la salida "linkeamos con permiso" tampoco existe
// (`docs/paywall-alumno-suelto.md` §7).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// APIs que abren algo fuera de la app. Un CTA de compra necesita alguna.
const _aperturasExternas = <String>[
  'package:url_launcher',
  'launchUrl(',
  'launchUrlString(',
  'WebViewController',
  'WebViewWidget',
  'InAppBrowser',
];

/// El código de [f] sin comentarios.
///
/// Sin esto el test se cae contra su propia documentación: los archivos del
/// paywall EXPLICAN en dartdoc por qué no puede haber un launcher, y nombrar
/// `launchUrl` en una explicación no es cablearlo. Es la misma lección que ya
/// aprendió el guard del entrenador.
///
/// Corta en el primer `//`, así que una línea con `launchUrl(Uri.parse(
/// 'https://…'))` queda truncada en `https:` — pero conserva el `launchUrl(`,
/// que es lo que se busca. No maneja comentarios de bloque `/* */`: no hay en
/// este repo, y si aparecen, el falso positivo es del lado seguro.
String _sinComentarios(File f) => f.readAsLinesSync().map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    }).join('\n');

List<File> _dartsDe(String ruta) => Directory(ruta)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

void main() {
  group('el paywall del alumno no abre nada afuera de la app', () {
    final dir = Directory('lib/features/paywall');

    test('la carpeta existe donde este test la busca', () {
      expect(dir.existsSync(), isTrue,
          reason: 'no encontré lib/features/paywall desde ${Directory.current}'
              ' — si se movió, movete este test con ella en vez de borrarlo');
    });

    test('ningún archivo del paywall puede abrir el navegador', () {
      final hallazgos = <String>[];
      for (final f in _dartsDe('lib/features/paywall')) {
        final codigo = _sinComentarios(f);
        for (final aguja in _aperturasExternas) {
          if (codigo.contains(aguja)) hallazgos.add('${f.path}: $aguja');
        }
      }

      expect(
        hallazgos,
        isEmpty,
        reason: 'el paywall del alumno abre algo afuera de la app. Bajo la '
            'Guideline 3.1.3(f) la app no puede linkear al checkout — ni con '
            'un botón, ni desde el `onUpgrade` de la hoja de límite:\n'
            '${hallazgos.join("\n")}',
      );
    });
  });

  group('quién puede abrir una URL en toda la app', () {
    // Allowlist, y a propósito.
    //
    // El guard por carpeta no alcanza: el `onUpgrade` de la hoja lo puede
    // construir CUALQUIER call site —hoy `routine_editor_screen` y
    // `routine_detail_screen`—, y ahí un `launchUrl` a la pasarela queda
    // afuera del scope de `lib/features/paywall/`.
    //
    // Entonces la pregunta se da vuelta: en vez de "esta carpeta no abre
    // nada", **el repo entero declara quién abre**. Agregar un launcher nuevo
    // pone rojo este test, y el que lo agrega tiene que escribir acá por qué
    // su destino no es un punto de venta. Ese medio minuto es el punto.
    //
    // Mismo patrón que `scripts/test/storage_scripts_destination.test.js`:
    // cuando la garantía vive en un archivo que nadie mira al revisar un PR,
    // el test lo mira.
    const permitidos = <String, String>{
      'lib/features/workout/presentation/widgets/exercise_video_player.dart':
          'abre el video del ejercicio en el reproductor del sistema cuando '
              'el embebido no puede — contenido, no compra',
      'lib/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart':
          'sólo Coach Hub WEB: abre archivos del alumno. La regla de Apple '
              'no aplica a la web, y esta pantalla no viaja en el binario móvil',
    };

    test('la lista de archivos que abren URLs es exactamente la declarada',
        () {
      final encontrados = <String>{};
      for (final f in _dartsDe('lib')) {
        final codigo = _sinComentarios(f);
        if (_aperturasExternas.any(codigo.contains)) {
          encontrados.add(f.path);
        }
      }

      final nuevos = encontrados.difference(permitidos.keys.toSet());
      expect(
        nuevos,
        isEmpty,
        reason: 'archivos nuevos abriendo algo afuera de la app:\n'
            '${nuevos.join("\n")}\n\n'
            'Si el destino NO es un punto de venta, sumalo a `permitidos` con '
            'su razón. Si LO ES, la app móvil no puede hacerlo: la Guideline '
            '3.1.3(f) la obliga a no linkear al checkout, y Argentina no está '
            'en el External Purchase Link Entitlement.',
      );

      final desaparecidos = permitidos.keys.toSet().difference(encontrados);
      expect(
        desaparecidos,
        isEmpty,
        reason: 'estos ya no abren nada: sacalos de `permitidos` para que la '
            'lista siga diciendo la verdad\n${desaparecidos.join("\n")}',
      );
    });
  });

  group('la hoja de límite sigue sin CTA de compra', () {
    // No es lo mismo que el guard de arriba. Ahí se prohíbe ABRIR algo; acá se
    // fija el estado de hoy: el botón todavía no se dibuja porque el checkout
    // del alumno no existe (`docs/paywall-alumno-suelto.md` §7.1).
    //
    // Cuando exista, este test se va a poner rojo — y eso está bien: es el
    // recordatorio de leer 3.1.3(f) antes de decidir qué hace el botón. Un CTA
    // que sólo EXPLICA que se paga por web es discutible pero defendible; uno
    // que abre la web, no.
    test('ningún call site pasa `onUpgrade`', () {
      final conCallback = <String>[];
      for (final f in _dartsDe('lib')) {
        if (f.path.endsWith('free_plan_limit_sheet.dart')) continue;
        final codigo = _sinComentarios(f);
        if (codigo.contains('onUpgrade')) conCallback.add(f.path);
      }

      expect(
        conCallback,
        isEmpty,
        reason: 'alguien cableó el CTA de la hoja de límite:\n'
            '${conCallback.join("\n")}\n\n'
            'Antes de que esto pase a verde: bajo 3.1.3(f) ese botón NO puede '
            'llevar al checkout. Actualizá este test explicando qué hace, y '
            'dejá el guard de `launchUrl` de arriba intacto.',
      );
    });
  });
}
