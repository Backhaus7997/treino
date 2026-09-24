import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/moderation/moderation_filter.dart';
import 'package:treino/core/moderation/vetted_terms.g.dart';
import 'package:treino/features/workout/domain/muscle_group.dart';

/// La lista ENTERA contra el filtro, y el vocabulario REAL del producto
/// contra el filtro. ESPEJO de
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
/// 2. Que el contenido REAL del producto pasa entero: el catalogo de
///    ejercicios, las plantillas de Explorar, los grupos musculares y todo el
///    texto de la app. TREINO habla del cuerpo todo el tiempo; un filtro que
///    rechaza `musculo` es peor que no tener filtro, porque el usuario no
///    entiende que hizo mal y se va.
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
    for (final (terminos, esperado) in porSeveridad) {
      for (final termino in terminos) {
        test('${esperado.name.padRight(6)} · "$termino"', () {
          // Todas las variantes de un termino en UN test, juntando las que se
          // escapan: un reporte que dice cuales pasaron vale mas que el primer
          // `expect` que falla.
          final escapadas = <String>[];
          variantes(termino).forEach((nombre, texto) {
            final obtenido = ModerationFilter.check(texto);
            if (obtenido != esperado) {
              escapadas.add('$nombre: "$texto" dio ${obtenido.name} '
                  '(normalizado: "${ModerationFilter.normalize(texto)}")');
            }
          });
          expect(escapadas, isEmpty, reason: escapadas.join('\n'));
        });
      }
    }
  });

  group('el vocabulario real del producto pasa entero', () {
    final textos = corpusReal();

    test('el corpus se cargo', () {
      // Si un archivo se mueve, el corpus queda vacio y el test de abajo pasa
      // sin haber mirado nada. El piso esta muy por debajo de lo que hay hoy
      // —el total exacto sale en el nombre del test de abajo— para que
      // agregar o sacar un ejercicio no lo rompa.
      expect(textos.length, greaterThan(6000));
    });

    test('ninguno de los ${textos.length} textos da block ni review', () {
      final caidos = [
        for (final (origen, texto) in textos)
          if (ModerationFilter.check(texto) != ModerationVerdict.ok)
            '${ModerationFilter.check(texto).name} · $origen: "$texto"',
      ];
      expect(caidos, isEmpty, reason: caidos.join('\n'));
    });
  });
}

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
    'leet 0 1 @ 3': termino
        .replaceAll('o', '0')
        .replaceAll('i', '1')
        .replaceAll('a', '@')
        .replaceAll('e', '3'),
    // Adornos pegados al termino completo. Una `@` en el borde a veces es una
    // `a` —`put@`— y a veces un adorno —`pija@`—: sin estas dos variantes, un
    // arreglo que cubre la primera lectura y rompe la segunda pasa verde. Ya
    // paso una vez, en la primera version de este PR.
    'arroba adelante': '@$termino',
    'arroba atras': '$termino@',
    'exclamacion atras': '$termino!',
    'dentro de una oracion': 'mirá vos, $termino, te lo digo en serio',
  };
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
List<(String, String)> corpusReal() {
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
