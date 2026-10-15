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

/// Dónde declara el backend la clave de los recordatorios de entrenamiento.
///
/// A diferencia de las de arriba, acá el test NO fija el NOMBRE de la constante:
/// pide que el archivo exporte ALGUNA `export const X = "<literal>"` cuyo valor
/// sea el de Dart. Lo que importa es el literal —es lo que lee el backend de
/// `notificationPrefs`—, no cómo se llame la variable que lo guarda.
const _archivoDeRecordatorios =
    'functions/src/notifications/notify-daily-reminders.ts';

/// Los nombres de las constantes exportadas por [fuente] cuyo valor es,
/// exactamente, el literal de texto [literal].
///
/// Mismas defensas que [extraerLiteralTs]: el ancla `^` va pegada a `export`,
/// así que una línea comentada (`// export const …`) o un JSDoc que cite la
/// declaración (` * export const …`) no cuentan. Tampoco cuenta una expresión
/// (`PREFIJO + "x"`): el valor tiene que ser el literal y nada más, porque este
/// scan no sabe evaluar nada.
///
/// Lista vacía = no hay ninguna. El que llama decide si eso es un fallo; acá
/// nunca se devuelve «todo bien» por no haber encontrado nada.
List<String> exportsConLiteral(String fuente, String literal) {
  final declaracion = RegExp(
    r'^export const (\w+)\s*(?::\s*string\s*)?=\s*(["\x27])'
    '${RegExp.escape(literal)}'
    r'\2\s*;?\s*(//.*)?$',
    multiLine: true,
  );
  return declaracion
      .allMatches(fuente)
      .map((m) => m.group(1)!)
      .toList(growable: false);
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

  // La fila de los recordatorios diarios de entrenamiento (push al atleta). La
  // lee el backend de `notificationPrefs.recordatorios_entrenamiento.push` y la
  // escribe el interruptor de Perfil › Privacidad: misma historia que arriba,
  // otra clave. Si el literal diverge, el atleta apaga el recordatorio y el
  // push sigue llegando.
  group(
      'la clave de recordatorios de entrenamiento no deriva entre Dart y '
      'TypeScript', () {
    test(
        '$_archivoDeRecordatorios exporta una constante == '
        'kPrefRecordatoriosEntrenamiento', () {
      final archivo = File(_archivoDeRecordatorios);
      if (!archivo.existsSync()) {
        fail(
          'No existe $_archivoDeRecordatorios (cwd: '
          '${Directory.current.path}). Si el archivo se movió, actualizá '
          '`_archivoDeRecordatorios`; si todavía no se escribió, el backend de '
          'los recordatorios diarios no existe y el interruptor de la app '
          'escribe una clave que nadie lee. Este test tiene que correr desde '
          'la raíz del repo.',
        );
      }

      final nombres = exportsConLiteral(
        archivo.readAsStringSync(),
        kPrefRecordatoriosEntrenamiento,
      );

      expect(
        nombres,
        isNotEmpty,
        reason: 'No encontré ningún `export const X = '
            '"$kPrefRecordatoriosEntrenamiento";` en $_archivoDeRecordatorios. '
            'La app escribe `notificationPrefs.$kPrefRecordatoriosEntrenamiento'
            '.push`: si el backend lee otra clave (o la arma con una expresión '
            'que este scan no sabe leer), apagar el interruptor no frenaría '
            'ningún push.',
      );
    });
  });

  // El lector de `exportsConLiteral` es lo que hace que ese test signifique
  // algo: si devolviera siempre una lista no vacía, o contara comentarios, el
  // test pasaría con el `.ts` roto.
  group('exportsConLiteral — no pasa en verde cuando no encuentra', () {
    const k = 'recordatorios_entrenamiento';

    test('lee comillas dobles, simples, anotación de tipo y comentario final',
        () {
      expect(
        exportsConLiteral('export const A = "$k";\n', k),
        ['A'],
      );
      expect(
        exportsConLiteral("export const B: string = '$k'; // la clave\n", k),
        ['B'],
      );
    });

    test('una línea comentada o un JSDoc NO cuentan', () {
      const fuente = '''
// export const VIEJA = "$k";
/**
 * export const TAMBIEN_VIEJA = "$k";
 */
''';
      expect(exportsConLiteral(fuente, k), isEmpty);
    });

    test('otro literal, un literal que lo CONTIENE o una expresión, tampoco',
        () {
      expect(exportsConLiteral('export const A = "otra_clave";\n', k), isEmpty);
      expect(exportsConLiteral('export const A = "${k}_v2";\n', k), isEmpty);
      expect(exportsConLiteral('export const A = P + "$k";\n', k), isEmpty);
    });

    test('un `const` sin `export` no cuenta: el contrato es lo exportado', () {
      expect(exportsConLiteral('const A = "$k";\n', k), isEmpty);
    });

    test('un archivo vacío devuelve lista vacía, no «todo bien»', () {
      expect(exportsConLiteral('', k), isEmpty);
    });
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
