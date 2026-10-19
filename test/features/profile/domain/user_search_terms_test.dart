import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/user_search_terms.dart';

/// El plegado de la consulta contra los vectores compartidos con la Cloud
/// Function que escribe `searchPrefixes` y con el backfill (#1478). Si este
/// test y el de la CF leen el mismo archivo y los dos pasan, la app pliega
/// "Martín" igual que el campo que consulta.
void main() {
  final vectores = jsonDecode(
    File('test/fixtures/search/user_search_terms.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final cases = (vectores['cases'] as List).cast<Map<String, dynamic>>();

  group('paridad con los vectores compartidos', () {
    test('usa los mismos topes que la CF', () {
      expect(kSearchPrefixMinLength, vectores['minPrefixLength']);
      expect(kSearchPrefixMaxLength, vectores['maxPrefixLength']);
    });

    for (final c in cases) {
      test('tokens de ${jsonEncode(c['input'])}', () {
        expect(searchTokens(c['input'] as String), c['tokens']);
      });
    }

    // La aguja de la consulta tiene que ser un prefijo que la CF guarda: si
    // no, el `array-contains` no encuentra nada aunque el nombre coincida.
    for (final c in cases) {
      final prefixes = (c['prefixes'] as List).cast<String>();
      for (final token in (c['tokens'] as List).cast<String>()) {
        if (token.length < kSearchPrefixMinLength) continue;
        test('la aguja de "$token" está entre lo que guarda la CF', () {
          // Sólo cuentan las palabras que la CF indexa (las 6 primeras).
          if (!prefixes.any(token.startsWith)) return;
          expect(prefixes, contains(searchNeedle([token])));
        });
      }
    }
  });

  group('searchNeedle', () {
    test('toma la palabra más larga, la más selectiva', () {
      expect(searchNeedle(['lo', 'martin']), 'martin');
    });

    test('trunca a $kSearchPrefixMaxLength, que es lo más largo que se guarda',
        () {
      expect(searchNeedle(['supercalifragilistico']), 'supercalifragil');
    });

    test('sin una palabra de 2 letras no hay aguja', () {
      expect(searchNeedle(['a', 'b']), isNull);
      expect(searchNeedle(const []), isNull);
    });
  });

  group('nameMatchesQuery', () {
    test('cada palabra de la consulta empieza alguna del nombre', () {
      expect(nameMatchesQuery('Martín López', ['martin', 'lo']), isTrue);
      expect(nameMatchesQuery('Martín López', ['lopez', 'martin']), isTrue);
      expect(nameMatchesQuery('Martín Gómez', ['martin', 'lo']), isFalse);
    });

    test('compara la palabra ENTERA aunque la aguja venga truncada', () {
      expect(
        nameMatchesQuery('Supercalifragilistico', ['supercalifragilistico']),
        isTrue,
      );
      expect(
        nameMatchesQuery('Supercalifragilisto', ['supercalifragilistico']),
        isFalse,
      );
    });

    test('un perfil sin nombre no coincide con nada', () {
      expect(nameMatchesQuery(null, ['ma']), isFalse);
    });
  });
}
