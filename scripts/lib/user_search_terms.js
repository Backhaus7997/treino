/**
 * user_search_terms.js — el plegado de nombres de la búsqueda de usuarios
 * (#1478), para los scripts: el backfill de `searchPrefixes` y el seed del
 * emulador.
 *
 * Es una COPIA de `functions/src/profile/user-search-prefixes.ts`, que es el
 * escritor de verdad (la Cloud Function). Los scripts no pueden importar de
 * `functions/` —es otro paquete, en TypeScript y compilado aparte—, así que la
 * paridad no la garantiza el import sino los vectores compartidos de
 * `test/fixtures/search/user_search_terms.json`: los leen este módulo, la CF y
 * la app. Si cambiás el plegado acá, cambialo en los tres y en los vectores.
 *
 * Por qué importa que sean idénticos: el backfill escribe lo que esta copia
 * calcula, y la CF, en la próxima escritura del perfil, compara contra lo que
 * ELLA calcula. Si difieren, la CF lo reescribe — no se rompe nada, pero el
 * backfill habría escrito de más.
 */

'use strict';

const SEARCH_PREFIX_MIN = 2;
const SEARCH_PREFIX_MAX = 15;
const SEARCH_MAX_TOKENS = 6;

/** Ver `searchTokens` en `functions/src/profile/user-search-prefixes.ts`. */
function searchTokens(text) {
  if (typeof text !== 'string') return [];
  const folded = text
    .toLowerCase()
    .replace(/[̀-ͯ]/g, '')
    .replace(/[áàäâãå]/g, 'a')
    .replace(/[éèëê]/g, 'e')
    .replace(/[íìïî]/g, 'i')
    .replace(/[óòöôõ]/g, 'o')
    .replace(/[úùüû]/g, 'u')
    .replace(/[ýÿ]/g, 'y')
    .replace(/ñ/g, 'n')
    .replace(/ç/g, 'c');
  const tokens = [];
  for (const t of folded.split(/[^a-z0-9]+/)) {
    if (t !== '' && !tokens.includes(t)) tokens.push(t);
  }
  return tokens;
}

/** Ver `searchPrefixesFor` en `functions/src/profile/user-search-prefixes.ts`. */
function searchPrefixesFor(displayName) {
  const out = [];
  const seen = new Set();
  const tokens = searchTokens(displayName)
    .filter((t) => t.length >= SEARCH_PREFIX_MIN)
    .slice(0, SEARCH_MAX_TOKENS);
  for (const t of tokens) {
    const top = Math.min(t.length, SEARCH_PREFIX_MAX);
    for (let n = SEARCH_PREFIX_MIN; n <= top; n++) {
      const p = t.slice(0, n);
      if (!seen.has(p)) {
        seen.add(p);
        out.push(p);
      }
    }
  }
  return out;
}

/** Ver `searchPrefixesToWrite` en `functions/src/profile/user-search-prefixes.ts`. */
function searchPrefixesToWrite(data) {
  if (data === undefined) return null;
  const wanted = searchPrefixesFor(data.displayName);
  const current = data.searchPrefixes;
  if (current === undefined || current === null) {
    return wanted.length === 0 ? null : wanted;
  }
  if (
    Array.isArray(current) &&
    current.length === wanted.length &&
    current.every((v, i) => v === wanted[i])
  ) {
    return null;
  }
  return wanted;
}

module.exports = {
  SEARCH_PREFIX_MIN,
  SEARCH_PREFIX_MAX,
  SEARCH_MAX_TOKENS,
  searchTokens,
  searchPrefixesFor,
  searchPrefixesToWrite,
};
