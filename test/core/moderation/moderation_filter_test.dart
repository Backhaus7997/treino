import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/moderation/moderation_filter.dart';
import 'package:treino/core/moderation/vetted_terms.g.dart';

/// Conformidad del filtro de terminos vetados.
///
/// El grueso de esta suite NO esta escrito aca: sale de `kVettedCases`, que se
/// genera desde `assets/moderation/terminos-vetados.json`. La suite de
/// TypeScript (`functions/src/moderation/__tests__/`) corre EXACTAMENTE los
/// mismos casos contra las mismas expectativas.
///
/// Esa es la parte que importa. El algoritmo es lo unico del filtro que esta
/// escrito dos veces, y un modelo con su espejo escrito a mano es como este
/// repo rompio la publicacion de posts durante siete semanas con la suite
/// entera en verde (`Post.reactionCounts`). Si Dart y TypeScript se separan,
/// una de las dos suites se cae.
void main() {
  group('corpus de conformidad (generado, compartido con TypeScript)', () {
    test('el corpus no esta vacio', () {
      // Sin esto, borrar los casos del JSON dejaria esta suite en verde sin
      // haber medido nada — y el verde se leeria como "las dos coinciden".
      expect(kVettedCases, isNotEmpty);
      expect(kVettedCases.length, greaterThanOrEqualTo(30));
    });

    for (final caso in kVettedCases) {
      final esperado =
          ModerationVerdict.values.firstWhere((v) => v.name == caso.espera);

      test('${caso.espera.padRight(6)} · "${caso.texto}"', () {
        // La forma normalizada se compara ADEMAS del veredicto, y sale de la
        // implementacion de referencia en el generador.
        //
        // Sin esto el corpus solo caza una divergencia cuando llega a voltear
        // un `ok` en `block`: dos normalizaciones distintas que no cruzan ese
        // umbral quedan vivas, con las dos suites en verde, hasta el dia que
        // alguien agrega un termino y el bug aparece lejos de donde se
        // escribio.
        expect(
          ModerationFilter.normalize(caso.texto),
          caso.normalizado,
          reason: 'la normalizacion de Dart se separo de la referencia',
        );
        expect(
          ModerationFilter.normalizeLoose(caso.texto),
          caso.normalizadoAmplio,
          reason: 'la lectura amplia de Dart se separo de la referencia',
        );
        expect(
          ModerationFilter.check(caso.texto),
          esperado,
          reason: caso.por.isEmpty
              ? null
              : '${caso.por}\n'
                  'normalizado: "${ModerationFilter.normalize(caso.texto)}"',
        );
      });
    }
  });

  group('normalizacion', () {
    test('minuscula, diacriticos y repeticiones', () {
      expect(ModerationFilter.normalize('PÚTOOOO'), 'puto');
      expect(ModerationFilter.normalize('Mogólico'), 'mogolico');
    });

    test('colapsa runs de tres o mas, no de dos', () {
      // `carro`, `perro`, `llave` y `accion` tienen dobles. Colapsarlas
      // romperia el castellano entero, y el filtro empezaria a comparar
      // contra palabras que nadie escribio.
      expect(ModerationFilter.normalize('carro'), 'carro');
      expect(ModerationFilter.normalize('perro'), 'perro');
      expect(ModerationFilter.normalize('holaaaa'), 'hola');
    });

    test('el leet de simbolos pide letra a los dos lados', () {
      // Con `!` traducido a lo bruto, `puta!` quedaria `putai` y dejaria de
      // matchear: el falso NEGATIVO mas facil de producir.
      expect(ModerationFilter.normalize('puta!'), 'puta!');
      expect(ModerationFilter.normalize('p!ja'), 'pija');
    });

    test('los digitos se traducen siempre', () {
      expect(ModerationFilter.normalize('p0to'), 'poto');
      expect(ModerationFilter.normalize('and4te'), 'andate');
    });

    test('la lectura amplia traduce @ y \$ en los bordes, y ! no', () {
      // `check` evalua las dos lecturas y gana la peor: la estricta caza
      // `pija@` (la `@` queda como separador) y la amplia caza `put@`.
      expect(ModerationFilter.normalize('put@'), 'put@');
      expect(ModerationFilter.normalizeLoose('put@'), 'puta');
      expect(ModerationFilter.normalizeLoose('@ndate'), 'andate');
      expect(ModerationFilter.normalizeLoose('puta\$'), 'putas');
      expect(ModerationFilter.normalizeLoose('puta!'), 'puta!');
    });
  });

  group('lo que el filtro NO hace', () {
    test('no pega el texto entero en la pasada antievasion', () {
      // `otroloco` contiene `trolo`. La implementacion ingenua —pegar todos
      // los tokens— bloquea castellano corriente.
      expect(ModerationFilter.check('otro loco'), ModerationVerdict.ok);
      expect(ModerationFilter.check('otro lote'), ModerationVerdict.ok);
    });

    test('no bloquea el vocabulario del producto', () {
      // Si esto se cae, el filtro es inusable: `musculo` esta en cada rutina.
      for (final texto in [
        'musculo',
        'musculos',
        'musculacion',
        'cuatro series al musculo dorsal',
        'calculo el volumen semanal',
      ]) {
        expect(ModerationFilter.check(texto), ModerationVerdict.ok,
            reason: 'bloqueo "$texto", que es vocabulario central de TREINO');
      }
    });

    test('block le gana a review', () {
      // `pelotudo` es `review`, `puto` es `block`. Juntos tiene que ganar el
      // mas severo, si no la severidad depende del orden del texto.
      expect(ModerationFilter.check('pelotudo puto'), ModerationVerdict.block);
      expect(ModerationFilter.check('puto pelotudo'), ModerationVerdict.block);
    });

    test('texto vacio o sin letras pasa', () {
      expect(ModerationFilter.check(''), ModerationVerdict.ok);
      expect(ModerationFilter.check('   '), ModerationVerdict.ok);
      expect(ModerationFilter.check('!!!'), ModerationVerdict.ok);
    });
  });
}
