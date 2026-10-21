/// Plegado de nombres de la búsqueda de usuarios (#1478), del lado de la
/// consulta.
///
/// El campo que se consulta, `userPublicProfiles/{uid}.searchPrefixes`, lo
/// escribe SÓLO una Cloud Function (`functions/src/profile/
/// user-search-prefixes.ts`): los prefijos de 2 a 15 letras de cada palabra del
/// nombre, plegada. "Martín López" → `ma … martin, lo … lopez`. La app no lo
/// escribe nunca — ni lo tiene en `UserPublicProfile`: `upsert` manda el modelo
/// con merge y lo pisaría.
///
/// PARIDAD: si esta función pliega distinto que la CF, la app busca "martin" y
/// el campo guarda otra cosa. Las tres copias (esta, la CF y
/// `scripts/lib/user_search_terms.js`) leen los mismos vectores de
/// `test/fixtures/search/user_search_terms.json`. Mismo esquema que
/// `normalize()` de `coach_hub/data/exercise_matcher.dart`: clases de
/// caracteres explícitas, y todo lo que no sea `[a-z0-9]` separa palabras.
library;

/// Prefijo más corto que guarda la CF.
const int kSearchPrefixMinLength = 2;

/// Prefijo más largo que guarda la CF. Una palabra de la consulta más larga se
/// trunca a esto para el `array-contains` y se termina de comparar entera con
/// [nameMatchesQuery].
const int kSearchPrefixMaxLength = 15;

/// Palabras de [text], plegadas: minúsculas, sin tildes ni diéresis, `ñ`→`n`,
/// `ç`→`c`, cortadas en todo lo que no sea `[a-z0-9]`. Sin repetidas, en el
/// orden en que aparecen.
///
/// El orden de las operaciones importa: minúsculas primero (para que `Á` sea
/// `á` antes de reemplazarla), después las marcas combinantes sueltas (un
/// teclado que manda "i" + U+0301), después las letras con tilde, y el corte
/// al final — antes se comería las letras con tilde como separadores.
List<String> searchTokens(String? text) {
  if (text == null) return const [];
  final folded = text
      .toLowerCase()
      .replaceAll(RegExp('[̀-ͯ]'), '')
      .replaceAll(RegExp('[áàäâãå]'), 'a')
      .replaceAll(RegExp('[éèëê]'), 'e')
      .replaceAll(RegExp('[íìïî]'), 'i')
      .replaceAll(RegExp('[óòöôõ]'), 'o')
      .replaceAll(RegExp('[úùüû]'), 'u')
      .replaceAll(RegExp('[ýÿ]'), 'y')
      .replaceAll('ñ', 'n')
      .replaceAll('ç', 'c');
  final tokens = <String>[];
  for (final t in folded.split(RegExp('[^a-z0-9]+'))) {
    if (t.isNotEmpty && !tokens.contains(t)) tokens.add(t);
  }
  return tokens;
}

/// El valor para `array-contains` sobre `searchPrefixes`: la palabra más larga
/// de la consulta (la más selectiva), truncada a [kSearchPrefixMaxLength].
/// `null` si ninguna llega a [kSearchPrefixMinLength]: la CF no guarda
/// prefijos de una letra, así que esa consulta no encontraría nada.
String? searchNeedle(List<String> queryTokens) {
  String? longest;
  for (final t in queryTokens) {
    if (longest == null || t.length > longest.length) longest = t;
  }
  if (longest == null || longest.length < kSearchPrefixMinLength) return null;
  return longest.length > kSearchPrefixMaxLength
      ? longest.substring(0, kSearchPrefixMaxLength)
      : longest;
}

/// Si cada palabra de la consulta es el principio de alguna palabra del
/// nombre. Es el filtro que completa al `array-contains`, que sólo puede
/// preguntar por UNA: "martin lo" encuentra a "Martín López" y no a "Martín
/// Gómez", y el orden no importa ("lopez martin" también).
bool nameMatchesQuery(String? displayName, List<String> queryTokens) {
  final nameTokens = searchTokens(displayName);
  return queryTokens.every((q) => nameTokens.any((n) => n.startsWith(q)));
}
