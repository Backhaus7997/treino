import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/notification_pref_keys.dart';

// La clave de preferencia de los correos comerciales vive en TypeScript (la
// lee el backend para decidir si manda) y en Dart (la escribe el interruptor
// de Perfil › Privacidad). Dos lenguas, dos archivos, ningún compilador que
// las compare: si una cambia sola, el interruptor escribe un campo que nadie
// lee y el usuario sigue recibiendo los correos que creyó apagar.
//
// Este test lee el `.ts` y compara. Es un SCAN TEXTUAL, y por eso se cuida de
// no pasar en verde cuando no encontró nada: si la línea cambia de forma, falla
// pidiendo que alguien mire, en vez de comparar contra «nada».

/// Dónde declara el backend la clave, y con qué nombre.
///
/// `free-limit-mail.ts` no está: importa `ATHLETE_PROSPECT_PREF_KEY` en vez de
/// repetir el literal, así que no puede divergir por su cuenta.
const _declaraciones = <({String archivo, String constante})>[
  (
    archivo: 'functions/src/subscriptions/athlete-prospect-mail.ts',
    constante: 'ATHLETE_PROSPECT_PREF_KEY',
  ),
  (
    archivo: 'functions/src/subscriptions/trainer-limit-mail.ts',
    constante: 'TRAINER_LIMIT_PREF_KEY',
  ),
];

/// El literal con el que [fuente] declara `export const [constante] = "…";`.
///
/// Tira un [StateError] con un mensaje que dice QUÉ buscar y dónde, si la
/// declaración no está, está más de una vez, o ya no es un literal de texto.
/// Un comentario o un JSDoc que mencione la línea no cuenta: el ancla `^` va
/// pegada a `export`, y ` * export const …` o `// export const …` no empiezan
/// así.
String extraerLiteralTs(String fuente, String constante, {String? archivo}) {
  final donde = archivo ?? 'el fuente';
  final declaracion = RegExp(
    '^export const ${RegExp.escape(constante)}\\s*(?::\\s*string\\s*)?=\\s*'
    r'(.*)$',
    multiLine: true,
  );
  final coincidencias = declaracion.allMatches(fuente).toList();

  if (coincidencias.isEmpty) {
    throw StateError(
      'No encontré `export const $constante = "…";` en $donde. Si la '
      'constante se renombró o se movió, actualizá `_declaraciones` en '
      'test/features/profile/notification_pref_keys_drift_test.dart; si '
      'se borró, la clave de preferencia ya no tiene dueño en el backend y '
      'este test no puede seguir protegiéndola.',
    );
  }
  if (coincidencias.length > 1) {
    throw StateError(
      '`export const $constante` aparece ${coincidencias.length} veces en '
      '$donde: no sé cuál es la que vale.',
    );
  }

  final resto = coincidencias.single.group(1)!.trim();
  final literal = RegExp(r'''^(["'])([^"'\\]*)\1\s*;?\s*(//.*)?$''');
  final m = literal.firstMatch(resto);
  if (m == null) {
    throw StateError(
      '`$constante` en $donde ya no es un literal de texto simple '
      '(`$resto`). Este test sólo sabe leer `"valor"`; si la clave ahora se '
      'arma con una expresión, hay que enseñarle o compararla de otra forma.',
    );
  }
  return m.group(2)!;
}

void main() {
  group('la clave de correos promocionales no deriva entre Dart y TypeScript',
      () {
    for (final d in _declaraciones) {
      test('${d.constante} (${d.archivo}) == kPrefCorreosPromocionales', () {
        final archivo = File(d.archivo);
        if (!archivo.existsSync()) {
          fail(
            'No existe ${d.archivo} (cwd: ${Directory.current.path}). Si el '
            'archivo se movió, actualizá `_declaraciones`; si el test corre '
            'desde otro directorio, tiene que correr desde la raíz del repo.',
          );
        }

        final enTs = extraerLiteralTs(
          archivo.readAsStringSync(),
          d.constante,
          archivo: d.archivo,
        );

        expect(
          enTs,
          kPrefCorreosPromocionales,
          reason: 'El backend lee `notificationPrefs.$enTs.email` y la app '
              'escribe `notificationPrefs.$kPrefCorreosPromocionales.email`: '
              'apagar el interruptor no frenaría ningún correo.',
        );
      });
    }
  });

  // El lector de arriba es lo que hace que el test de deriva signifique algo.
  // Si `extraerLiteralTs` devolviera siempre lo que esperamos, o no fallara
  // cuando no encuentra nada, el test pasaría con el `.ts` roto.
  group('extraerLiteralTs — no pasa en verde cuando no encuentra', () {
    test('lee un literal con comillas dobles', () {
      expect(
        extraerLiteralTs('export const K = "novedades_plan";\n', 'K'),
        'novedades_plan',
      );
    });

    test('lee comillas simples y una anotación de tipo', () {
      expect(
        extraerLiteralTs("export const K: string = 'otra_clave';", 'K'),
        'otra_clave',
      );
    });

    test('un comentario al final de la línea no estorba', () {
      expect(
        extraerLiteralTs('export const K = "x"; // la clave\n', 'K'),
        'x',
      );
    });

    test('si la constante no está, FALLA con un mensaje claro', () {
      expect(
        () => extraerLiteralTs('export const OTRA = "x";\n', 'K'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('No encontré'), contains('K')),
          ),
        ),
      );
    });

    test('una línea comentada NO cuenta como declaración', () {
      const fuente = '''
// export const K = "vieja";
/**
 * export const K = "tambien_vieja";
 */
''';
      expect(
        () => extraerLiteralTs(fuente, 'K'),
        throwsA(isA<StateError>()),
      );
    });

    test('un valor armado con una expresión FALLA en vez de compararse', () {
      expect(
        () => extraerLiteralTs('export const K = PREFIJO + "x";\n', 'K'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('ya no es un literal'),
          ),
        ),
      );
    });

    test('dos declaraciones son ambiguas y FALLAN', () {
      expect(
        () => extraerLiteralTs(
          'export const K = "a";\nexport const K = "b";\n',
          'K',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('2 veces'),
          ),
        ),
      );
    });

    test('un nombre que es prefijo de otro no se confunde', () {
      // `K` no puede leer `KK`: el regex exige el `\s*=` justo después.
      expect(
        () => extraerLiteralTs('export const KK = "x";\n', 'K'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
