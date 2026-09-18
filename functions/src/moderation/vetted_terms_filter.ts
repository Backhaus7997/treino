import {
  VETTED_ALLOWLIST,
  VETTED_ANTI_EVASION,
  VETTED_BLOCK_PHRASES,
  VETTED_BLOCK_WORDS,
  VETTED_COLLAPSE_MIN,
  VETTED_FOLD,
  VETTED_LEET,
  VETTED_LEET_ONLY_BETWEEN_LETTERS,
  VETTED_REVIEW_PHRASES,
  VETTED_REVIEW_WORDS,
} from "./vetted_terms.g";

/** Que hacer con un texto que el usuario esta por publicar. */
export type ModerationVerdict = "ok" | "review" | "block";

/**
 * Filtrado de terminos vetados — ESPEJO de
 * `lib/core/moderation/moderation_filter.dart`.
 *
 * ## Por que existe un espejo
 *
 * El filtro del cliente es el que tecnicamente satisface la App Store Review
 * Guideline 1.2 —el contenido no llega a postearse— pero se saltea con el SDK
 * directo. Esta copia corre del lado del servidor, donde no hay nada que
 * saltear.
 *
 * ## Que NO esta escrito dos veces
 *
 * Las listas, el mapa de plegado, el de leet y el corpus de conformidad salen
 * los dos de `assets/moderation/terminos-vetados.json` en la misma corrida de
 * `scripts/build_moderation_list.py`, y un gate de CI rompe el PR si alguien
 * edita el JSON y no regenera.
 *
 * Lo unico escrito dos veces es este algoritmo. Es lo que el corpus de
 * `VETTED_CASES` vigila: la suite de Dart y la de TypeScript corren
 * EXACTAMENTE los mismos casos contra las mismas expectativas, asi que si las
 * dos implementaciones se separan, una de las dos se pone roja.
 *
 * Eso no es paranoia de manual. Este repo separo un modelo de su espejo tres
 * veces —`Block.toJson()`, `feedbackCounts` (#1160) y `Post.reactionCounts`—
 * y la tercera rompio la publicacion de posts durante siete semanas con la
 * suite entera en verde.
 */

/**
 * El veredicto para `text`.
 *
 * NO dice que termino lo disparo, a proposito: devolverlo convierte al filtro
 * en un oraculo para encontrarle el borde.
 */
export function checkText(text: string): ModerationVerdict {
  const tokens = toTokens(normalize(text));
  if (tokens.length === 0) return "ok";

  // --- Pasada A: palabra completa ----------------------------------------
  //
  // Por palabra y no por subcadena porque `musculo` contiene `culo` y
  // `computadora` contiene `puta`. Con `includes()` se bloquean las dos, y en
  // una app de entrenamiento `musculo` aparece en cada rutina.
  for (const t of tokens) {
    if (VETTED_BLOCK_WORDS.has(t)) return "block";
  }
  if (hasPhrase(tokens, VETTED_BLOCK_PHRASES)) return "block";

  // --- Pasada B: antievasion ---------------------------------------------
  if (evades(tokens)) return "block";

  // --- Pasada A, severidad `review` --------------------------------------
  for (const t of tokens) {
    if (VETTED_REVIEW_WORDS.has(t)) return "review";
  }
  if (hasPhrase(tokens, VETTED_REVIEW_PHRASES)) return "review";

  return "ok";
}

/**
 * Minuscula, sin diacriticos, sin leet y sin repeticiones.
 *
 * Exportada porque los tests la miden aparte del veredicto: cuando un caso del
 * corpus falla, saber en que quedo el texto es la diferencia entre arreglarlo
 * y adivinar.
 */
export function normalize(text: string): string {
  return collapse(leet(fold(text.toLowerCase())));
}

// -- pasos de la normalizacion --------------------------------------------

function fold(s: string): string {
  let out = "";
  for (const ch of s) out += VETTED_FOLD[ch] ?? ch;
  return out;
}

function leet(s: string): string {
  const chars = [...s];
  let out = "";
  for (let i = 0; i < chars.length; i++) {
    const ch = chars[i];
    const rep = VETTED_LEET[ch];
    if (rep === undefined) {
      out += ch;
      continue;
    }
    // Los simbolos (`@`, `$`, `!`) solo se traducen con letra a los DOS lados.
    // Sin esa regla `puta!` normaliza a `putai`, que no matchea `puta` por
    // palabra completa: el leet a lo bruto produce falsos NEGATIVOS sobre el
    // texto mas comun que existe, un insulto con signo de exclamacion.
    if (VETTED_LEET_ONLY_BETWEEN_LETTERS.has(ch)) {
      const antes = i > 0 && isAlnum(chars[i - 1]);
      const despues = i + 1 < chars.length && isAlnum(chars[i + 1]);
      out += antes && despues ? rep : ch;
    } else {
      out += rep;
    }
  }
  return out;
}

function collapse(s: string): string {
  const chars = [...s];
  let out = "";
  let i = 0;
  while (i < chars.length) {
    let j = i;
    while (j < chars.length && chars[j] === chars[i]) j++;
    const largo = j - i;
    out += largo >= VETTED_COLLAPSE_MIN ? chars[i] : chars[i].repeat(largo);
    i = j;
  }
  return out;
}

function isAlnum(ch: string): boolean {
  if (ch.length !== 1) return false;
  const c = ch.charCodeAt(0);
  return (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x7a);
}

const SEPARADORES = /[^0-9a-z]+/;

function toTokens(normalized: string): string[] {
  return normalized.split(SEPARADORES).filter((t) => t.length > 0);
}

// -- las dos pasadas -------------------------------------------------------

function hasPhrase(
  tokens: readonly string[],
  phrases: readonly (readonly string[])[],
): boolean {
  for (const phrase of phrases) {
    if (phrase.length > tokens.length) continue;
    for (let i = 0; i + phrase.length <= tokens.length; i++) {
      let match = true;
      for (let j = 0; j < phrase.length; j++) {
        if (tokens[i + j] !== phrase[j]) {
          match = false;
          break;
        }
      }
      if (match) return true;
    }
  }
  return false;
}

/**
 * La pasada antievasion.
 *
 * Hace dos cosas, y es importante lo que NO hace:
 *
 * 1. Junta las corridas de tokens de UN caracter. `p u t o` y `p-u-t-o` dan
 *    cuatro tokens de un caracter, y pegados dan `puto`.
 * 2. Busca cada termino de `VETTED_ANTI_EVASION` como subcadena de cada
 *    token, salteando los que estan en `VETTED_ALLOWLIST`.
 *
 * Lo que no hace es pegar el texto entero. Esa version —la obvia— bloquea
 * `otro loco`, porque `otroloco` contiene `trolo`. Tambien `otro lote`. Los
 * dos son castellano rioplatense corriente y los dos estan en el corpus.
 */
function evades(tokens: readonly string[]): boolean {
  const candidatos: string[] = [];
  let corrida = "";

  const cerrarCorrida = (): void => {
    if (corrida.length > 1) candidatos.push(corrida);
    corrida = "";
  };

  for (const t of tokens) {
    if (t.length === 1) {
      corrida += t;
      continue;
    }
    cerrarCorrida();
    // La allowlist no puede aportar letras a un match: `computo` contiene
    // `puto` y `controlo` contiene `trolo`, y las dos son palabras normales.
    if (!VETTED_ALLOWLIST.has(t)) candidatos.push(t);
  }
  cerrarCorrida();

  for (const c of candidatos) {
    for (const termino of VETTED_ANTI_EVASION) {
      if (c.includes(termino)) return true;
    }
  }
  return false;
}
