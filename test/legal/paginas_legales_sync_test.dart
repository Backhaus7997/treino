// Guard de deriva entre el texto legal de la app y las páginas públicas.
//
// `web/legal/*.html` las genera `tool/build_legal_pages.dart` a partir de
// `legal_content.dart`. Nada obliga a correr el generador: alguien edita el
// Dart, commitea, y las páginas de la tienda quedan con el texto viejo.
//
// Eso no es un detalle de sincronismo. La política de privacidad que declarás
// en App Store y Play es un compromiso legal, y la que el usuario aceptó en la
// app es otro. Que digan cosas distintas es exactamente el problema.
//
// Este test es el que avisa, en vez de un usuario o un revisor de tienda.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/features/auth/presentation/legal/legal_content.dart';

/// Normaliza para comparar: el generador colapsa el wrapping del código fuente
/// a un solo espacio, así que el Dart y el HTML no coinciden byte a byte.
String _norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

String _hex(Color c) {
  String ch(double v) =>
      (v * 255).round().toRadixString(16).padLeft(2, '0').toUpperCase();
  return '#${ch(c.r)}${ch(c.g)}${ch(c.b)}';
}

void main() {
  final privacidad = File('web/legal/privacidad.html');
  final terminos = File('web/legal/terminos.html');
  final estilo = File('web/legal/_estilo.css');
  final borrado = File('web/legal/eliminar-cuenta.html');

  group('las páginas legales existen', () {
    test('las cuatro están en el repo', () {
      // Se commitean a propósito: Hosting sirve `build/web`, y `flutter build
      // web` copia `web/` adentro. Si faltan, la URL que declaraste en la
      // tienda devuelve 404.
      for (final f in [privacidad, terminos, estilo, borrado]) {
        expect(f.existsSync(), isTrue, reason: '${f.path} no existe');
      }
    });
  });

  group('el HTML no derivó del Dart', () {
    test('privacidad.html tiene las ${kPrivacySections.length} secciones', () {
      final html = _norm(privacidad.readAsStringSync());
      for (final s in kPrivacySections) {
        expect(html, contains(_norm(s.heading)),
            reason: 'falta el título "${s.heading}" — '
                'corré `dart run tool/build_legal_pages.dart`');
        expect(html, contains(_norm(s.body)),
            reason: 'el cuerpo de "${s.heading}" no coincide con el Dart — '
                'corré `dart run tool/build_legal_pages.dart`');
      }
    });

    test('terminos.html tiene las ${kTermsSections.length} secciones', () {
      final html = _norm(terminos.readAsStringSync());
      for (final s in kTermsSections) {
        expect(html, contains(_norm(s.heading)),
            reason: 'falta el título "${s.heading}" — '
                'corré `dart run tool/build_legal_pages.dart`');
        expect(html, contains(_norm(s.body)),
            reason: 'el cuerpo de "${s.heading}" no coincide con el Dart — '
                'corré `dart run tool/build_legal_pages.dart`');
      }
    });

    test('las dos muestran la fecha y el contacto del Dart', () {
      for (final f in [privacidad, terminos]) {
        final html = f.readAsStringSync();
        expect(html, contains(kLegalLastUpdated),
            reason: '${f.path} quedó con una fecha vieja');
        expect(html, contains(kLegalContactEmail));
      }
    });

    test('ninguna se editó a mano: conservan el banner de generado', () {
      for (final f in [privacidad, terminos, estilo]) {
        expect(f.readAsStringSync(), contains('GENERADO'),
            reason: '${f.path} perdió el banner — ¿lo editaron a mano?');
      }
    });
  });

  group('la marca de las páginas no derivó de la paleta', () {
    // El generador corre en la VM de Dart pelada y no puede importar la
    // paleta (`Color` vive en `dart:ui`), así que los hex están escritos a
    // mano en el tool. Esto es lo que impide que se separen.
    const p = AppPalette.mintMagenta;
    final css = estilo.readAsStringSync();

    String tokenDelCss(String nombre) {
      final m = RegExp('$nombre:\\s*(#[0-9A-Fa-f]{6})').firstMatch(css);
      expect(m, isNotNull, reason: 'no encontré $nombre en _estilo.css');
      return m!.group(1)!.toUpperCase();
    }

    test('--ink es el bg de la paleta dark', () {
      expect(tokenDelCss('--ink'), _hex(p.bg));
    });
    test('--card es el bgCard', () {
      expect(tokenDelCss('--card'), _hex(p.bgCard));
    });
    test('--mint es el accent', () {
      expect(tokenDelCss('--mint'), _hex(p.accent));
    });
    test('--bone es el textPrimary', () {
      expect(tokenDelCss('--bone'), _hex(p.textPrimary));
    });
  });

  group('borrado de cuenta — lo que Play mira', () {
    final html = borrado.readAsStringSync();

    test('ofrece una vía que NO necesita la app instalada', () {
      // El punto entero de la página: Apple se conforma con el borrado in-app,
      // Play no. Si acá sólo dijera "entrá a la app", no cumpliría.
      expect(html, contains('mailto:'));
      expect(html, contains(kLegalContactEmail));
    });

    test('dice qué se borra y qué puede quedar', () {
      expect(html, contains('Qué se borra'));
      expect(html, contains('Qué puede quedar'));
    });

    test('linkea a la política de privacidad', () {
      expect(html, contains('/legal/privacidad.html'));
    });
  });
}
