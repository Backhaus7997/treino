import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/moderation/moderation_filter.dart';
import 'package:treino/core/moderation/vetted_terms.g.dart';
import 'package:treino/features/workout/domain/muscle_group.dart';

/// La lista ENTERA contra el filtro, y el texto legitimo contra el filtro.
/// ESPEJO de
/// `functions/src/__tests__/vetted-terms-lista-completa.test.ts`.
///
/// `moderation_filter_test.dart` corre el corpus de conformidad: casos
/// elegidos a mano que prueban el ALGORITMO. Esta suite prueba las otras dos
/// cosas, que ese corpus no puede:
///
/// 1. Que CADA termino de la lista da su severidad, escrito normal y con cada
///    variante de evasion que la normalizacion dice cubrir. Una entrada que el
///    filtro no caza se ve en el diff y parece defender algo: es cobertura que
///    no existe. Asi estuvieron 79 terminos, que escritos `p-i-j-a` pasaban.
/// 2. Que el texto legitimo pasa entero: el contenido REAL del producto —el
///    catalogo de ejercicios, las plantillas de Explorar, los grupos
///    musculares y todo el texto de la app— y texto del tipo que escribe un
///    usuario —mails, links, arrobas, telefonos—. TREINO habla del cuerpo
///    todo el tiempo; un filtro que rechaza `musculo` es peor que no tener
///    filtro, porque el usuario no entiende que hizo mal y se va.
void main() {
  final block = <String>[
    ...kVettedBlockWords,
    for (final frase in kVettedBlockPhrases) frase.join(' '),
  ];
  final review = <String>[
    ...kVettedReviewWords,
    for (final frase in kVettedReviewPhrases) frase.join(' '),
  ];
  final porSeveridad = [
    (block, ModerationVerdict.block),
    (review, ModerationVerdict.review),
  ];

  group('cada termino de la lista', () {
    test('la lista no esta vacia', () {
      // Sin esto, una lista vaciada por error deja la suite en verde sin
      // haber medido nada, y el verde se lee como "todo cubierto".
      expect(block.length, greaterThanOrEqualTo(60));
      expect(review.length, greaterThanOrEqualTo(25));
    });

    for (final (terminos, esperado) in porSeveridad) {
      for (final termino in terminos) {
        test('${esperado.name.padRight(6)} · "$termino"', () {
          expect(ModerationFilter.check(termino), esperado);
        });
      }
    }
  });

  group('cada termino con cada variante de evasion', () {
    test('los huecos conocidos nombran terminos y variantes que existen', () {
      // Sin esto, un typo en `huecosConocidos` exime una variante que no
      // existe —no exime nada— y la lista aparenta documentar algo.
      final todos = {...block, ...review};
      for (final MapEntry(key: termino, value: nombres)
          in huecosConocidos.entries) {
        expect(todos, contains(termino));
        expect(variantes(termino).keys, containsAll(nombres));
      }
    });

    for (final (terminos, esperado) in porSeveridad) {
      for (final termino in terminos) {
        test('${esperado.name.padRight(6)} · "$termino"', () {
          // Todas las variantes de un termino en UN test, juntando las que se
          // escapan: un reporte que dice cuales pasaron vale mas que el primer
          // `expect` que falla.
          final huecos = huecosConocidos[termino] ?? const <String>{};
          final escapadas = <String>[];
          final huecosCerrados = <String>[];
          variantes(termino).forEach((nombre, texto) {
            final obtenido = ModerationFilter.check(texto);
            if (huecos.contains(nombre)) {
              if (obtenido == esperado) huecosCerrados.add('$nombre: "$texto"');
            } else if (obtenido != esperado) {
              escapadas.add('$nombre: "$texto" dio ${obtenido.name} '
                  '(normalizado: "${ModerationFilter.normalize(texto)}")');
            }
          });
          expect(escapadas, isEmpty, reason: escapadas.join('\n'));
          expect(
            huecosCerrados,
            isEmpty,
            reason: 'El filtro ya caza estos huecos conocidos: sacalos de '
                '`huecosConocidos`.\n${huecosCerrados.join('\n')}',
          );
        });
      }
    }
  });

  group('el texto legitimo pasa entero', () {
    // Dos poblaciones, con piso propio cada una: si una se vacia, el total de
    // la otra no puede taparlo.
    //
    // El contenido PROPIO solo no alcanza. El filtro corre sobre lo que
    // escriben los usuarios —chats, bios, posts—, que tiene mails, links,
    // arrobas y telefonos; el catalogo no tiene ninguno. Con esa unica fuente
    // el corpus daba verde tanto si el filtro rompia mails como si no, y
    // `juan@computo.com` daba `block` en main sin que nadie se enterara.
    for (final (nombre, textos, piso) in [
      ('contenido propio', corpusPropio(), 6000),
      ('texto de usuario', corpusDeUsuario(), 1000),
    ]) {
      test('$nombre: el corpus se cargo', () {
        // Si un archivo se mueve, el corpus queda vacio y el test de abajo
        // pasa sin haber mirado nada. El piso esta muy por debajo de lo que
        // hay hoy —el total exacto sale en el nombre del test de abajo—
        // para que agregar o sacar un texto no lo rompa.
        expect(textos.length, greaterThan(piso));
      });

      test(
          '$nombre: ninguno de los ${textos.length} textos da block ni '
          'review', () {
        final caidos = [
          for (final (origen, texto) in textos)
            if (ModerationFilter.check(texto) != ModerationVerdict.ok)
              '${ModerationFilter.check(texto).name} · $origen: "$texto"',
        ];
        expect(caidos, isEmpty, reason: caidos.join('\n'));
      });
    }
  });
}

/// Variantes que el filtro NO caza, a sabiendas: el mismo `HUECO CONOCIDO`
/// que `con-chudo` en el JSON fuente. Dos clases, las dos explicadas en
/// `LEET_TAMBIEN_EN_BORDES` (scripts/build_moderation_list.py), y con un caso
/// de cada una en el corpus de conformidad:
///
/// - La lectura se elige para TODO el texto, no palabra por palabra. Una
///   frase que pide la `@` como adorno en el borde de una palabra y como
///   letra en el mismo borde de otra (`@c0lg@t3 d3 un @rb0l`) no tiene
///   lectura que acierte las dos.
/// - Dos o mas sustituciones seguidas en el borde MAS un adorno (`tet@$!`).
///
/// Estan FIJADAS: el test exige que sigan pasando. Si un cambio las empieza
/// a cazar se pone rojo, para que las saques de aca: una lista de huecos que
/// ya no son huecos le hace creer al proximo que el filtro cubre menos de lo
/// que cubre. Mismo mapa en el espejo de TypeScript.
const huecosConocidos = <String, Set<String>>{
  'colgate de un arbol': {'arroba adelante + leet'},
  'pro ana': {'arroba adelante + leet'},
  'ojala te mueras': {'leet + arroba atras', 'signos + exclamacion atras'},
  'manga de inutiles': {'leet + arroba atras'},
  'muerta de hambre': {'leet + arroba atras', 'signos + exclamacion atras'},
  'vomitar despues de comer': {'signos + exclamacion atras'},
  'pornografia': {'signos + exclamacion atras'},
  'promia': {'signos + exclamacion atras'},
  'tetas': {'signos + exclamacion atras'},
  'te voy a cagar a trompadas': {'signos + exclamacion atras'},
};

/// Las variantes de evasion que la normalizacion dice cubrir, aplicadas a UN
/// termino ya normalizado (minuscula, sin acentos). Mismo algoritmo que
/// `variantes()` en el espejo de TypeScript.
///
/// Los separadores van ENTRE LAS LETRAS de cada palabra, que es la evasion
/// que el filtro promete cubrir. Partir una palabra en dos pedazos largos
/// —`con-chudo`— es un hueco conocido y documentado en el JSON fuente.
Map<String, String> variantes(String termino) {
  const acentos = {'a': 'á', 'e': 'é', 'i': 'í', 'o': 'ó', 'u': 'ú'};
  final letras = termino.split('');
  String entreLetras(String separador) => termino
      .split(' ')
      .map((palabra) => palabra.split('').join(separador))
      .join(' ');
  final leet = termino
      .replaceAll('o', '0')
      .replaceAll('i', '1')
      .replaceAll('a', '@')
      .replaceAll('e', '3');
  final signos =
      termino.replaceAll('i', '!').replaceAll('s', '\$').replaceAll('a', '@');

  return {
    'mayusculas': termino.toUpperCase(),
    'mayusculas alternadas': [
      for (var i = 0; i < letras.length; i++)
        i.isOdd ? letras[i].toUpperCase() : letras[i],
    ].join(),
    'acentos': letras.map((c) => acentos[c] ?? c).join(),
    'dieresis': termino.replaceAll('u', 'ü'),
    'espacios entre letras': entreLetras(' '),
    'guiones entre letras': entreLetras('-'),
    'puntos entre letras': entreLetras('.'),
    'leet 0 1 @ 3': leet,
    'signos ! \$ @ por letras': signos,
    // Adornos pegados al termino completo, solos y encima de una
    // sustitucion. Una `@` en el borde a veces es una `a` —`put@`—, a veces
    // un adorno —`pija@`— y a veces las dos —`put@@`—: cada arreglo que
    // cubrio solo una de las tres paso verde sin estas variantes. Paso mas de
    // una vez en este PR.
    'arroba adelante': '@$termino',
    'arroba atras': '$termino@',
    'exclamacion atras': '$termino!',
    'leet + arroba atras': '$leet@',
    'arroba adelante + leet': '@$leet',
    'signos + exclamacion atras': '$signos!',
    'dentro de una oracion': 'mirá vos, $termino, te lo digo en serio',
  };
}

/// Texto del TIPO que escribe un usuario —mails, links, arrobas, telefonos,
/// abreviaturas—, desde `test/fixtures/moderation/texto-de-usuario.json`.
/// Mismo algoritmo de expansion que el espejo de TypeScript: cada usuario con
/// cada dominio, solo y dentro de la oracion del fixture.
List<(String, String)> corpusDeUsuario() {
  final fixture = jsonDecode(
    File('test/fixtures/moderation/texto-de-usuario.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final correos = fixture['correos'] as Map<String, dynamic>;
  final oracion = correos['oracion'] as String;
  final textos = <(String, String)>[];
  for (final usuario in (correos['usuarios'] as List).cast<String>()) {
    for (final dominio in (correos['dominios'] as List).cast<String>()) {
      final correo = '$usuario@$dominio';
      textos.add(('usuario · correo', correo));
      textos.add(('usuario · correo', oracion.replaceAll('{correo}', correo)));
    }
  }
  final resto = fixture['textos'] as Map<String, dynamic>;
  resto.forEach((categoria, lista) {
    for (final texto in (lista as List).cast<String>()) {
      textos.add(('usuario · $categoria', texto));
    }
  });
  return textos;
}

/// El contenido que el producto YA publica, con su origen para poder
/// encontrarlo si un texto se cae.
///
/// - `enriched-catalog.json`: el catalogo de ejercicios que suben
///   `scripts/import_enriched_catalog.js` y los seeds. Nombre, alias y
///   tecnica —todo lo que el usuario lee—, no ids ni urls.
/// - `improved-templates.json`: las plantillas de Explorar, que siembra
///   `scripts/seed_templates.js`.
/// - Los ARB en castellano: todo el texto de la app.
/// - [MuscleGroup]: las etiquetas de los grupos musculares, que viven en
///   codigo y no en un ARB.
List<(String, String)> corpusPropio() {
  final textos = <(String, String)>[];
  void agregar(String origen, Object? valor) {
    if (valor is String && valor.trim().isNotEmpty) {
      textos.add((origen, valor));
    }
  }

  Object? leer(String ruta) => jsonDecode(File(ruta).readAsStringSync());

  final catalogo = leer('docs/video-catalog-audit/enriched-catalog.json');
  for (final e in (catalogo as List).cast<Map<String, dynamic>>()) {
    final id = e['id'];
    agregar('catalogo $id · name', e['name']);
    for (final alias in e['aliases'] as List? ?? const []) {
      agregar('catalogo $id · alias', alias);
    }
    for (final paso in e['techniqueInstructions'] as List? ?? const []) {
      agregar('catalogo $id · tecnica', paso);
    }
  }

  final plantillas = leer('docs/video-catalog-audit/improved-templates.json');
  for (final p in (plantillas as List).cast<Map<String, dynamic>>()) {
    final id = p['id'];
    for (final campo in ['name', 'summary', 'split']) {
      agregar('plantilla $id · $campo', p[campo]);
    }
    final dias = (p['days'] as List? ?? const []).cast<Map<String, dynamic>>();
    for (final dia in dias) {
      agregar('plantilla $id · dia', dia['name']);
      final slots =
          (dia['slots'] as List? ?? const []).cast<Map<String, dynamic>>();
      for (final slot in slots) {
        agregar('plantilla $id · ejercicio', slot['exerciseName']);
        agregar('plantilla $id · nota', slot['notes']);
      }
    }
  }

  for (final ruta in ['lib/l10n/intl_es_AR.arb', 'lib/l10n/intl_es.arb']) {
    final arb = leer(ruta) as Map<String, dynamic>;
    arb.forEach((clave, valor) {
      if (!clave.startsWith('@')) agregar('$ruta · $clave', valor);
    });
  }

  for (final grupo in MuscleGroup.values) {
    agregar('MuscleGroup.${grupo.name}', grupo.label);
  }

  return textos;
}
