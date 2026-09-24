import {
  VETTED_ALLOWLIST,
  VETTED_ANTI_EVASION,
  VETTED_BLOCK_PHRASES,
  VETTED_BLOCK_WORDS,
  VETTED_COLLAPSE_MIN,
  VETTED_COMBINING_RANGES,
  VETTED_FOLD,
  VETTED_JOIN_MAX_FRAGMENT,
  VETTED_LEET,
  VETTED_LEET_ALSO_AT_EDGES,
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
  // Un simbolo pegado al borde de una palabra es ambiguo: en `put@` la `@` es
  // una `a`, en `pija@` es un adorno, en `put@@` son las dos cosas y en
  // `@p1j@` es adorno adelante y letra atras. Ninguna lectura sola cubre todo,
  // asi que se evaluan todas y gana la peor. Ver `VETTED_LEET_ALSO_AT_EDGES`.
  let peor: ModerationVerdict = "ok";
  for (const lectura of readings(text)) {
    const veredicto = verdictOf(toTokens(lectura));
    if (SEVERIDAD[veredicto] > SEVERIDAD[peor]) peor = veredicto;
    if (peor === "block") break;
  }
  return peor;
}

/** Orden de severidad, para quedarse con el peor de varios veredictos. */
const SEVERIDAD: Readonly<Record<ModerationVerdict, number>> = {
  ok: 0,
  review: 1,
  block: 2,
};

/** El veredicto para un texto ya normalizado y partido en tokens. */
function verdictOf(tokens: readonly string[]): ModerationVerdict {
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

  // --- Pasada C: letras sueltas ------------------------------------------
  const deletreado = spelledOut(tokens);
  if (deletreado === "block") return "block";

  // --- Pasada A, severidad `review` --------------------------------------
  for (const t of tokens) {
    if (VETTED_REVIEW_WORDS.has(t)) return "review";
  }
  if (hasPhrase(tokens, VETTED_REVIEW_PHRASES)) return "review";

  return deletreado ?? "ok";
}

/**
 * Minuscula, sin diacriticos, sin leet y sin repeticiones.
 *
 * Exportada porque los tests la miden aparte del veredicto: cuando un caso del
 * corpus falla, saber en que quedo el texto es la diferencia entre arreglarlo
 * y adivinar.
 */
export function normalize(text: string): string {
  return normalizar(text, "estricta");
}

/**
 * Las lecturas de un texto, en el orden del corpus. Ver
 * `LEET_TAMBIEN_EN_BORDES` en el generador.
 */
type Lectura = "estricta" | "prefijo" | "sufijo" | "adyacente" | "total";
const LECTURAS: readonly Lectura[] = [
  "estricta", "prefijo", "sufijo", "adyacente", "total",
];

/**
 * Las lecturas que evalua `checkText`, sin repetidas: la estricta —que es
 * `normalize`—, prefijo, sufijo, adyacente y total. Solo difieren cuando el
 * texto tiene alguno de `VETTED_LEET_ALSO_AT_EDGES`. Exportada por el mismo
 * motivo que `normalize`.
 */
export function readings(text: string): string[] {
  const out: string[] = [];
  for (const lectura of LECTURAS) {
    const forma = normalizar(text, lectura);
    if (!out.includes(forma)) out.push(forma);
  }
  return out;
}

function normalizar(text: string, lectura: Lectura): string {
  return collapse(leet(fold(text.toLowerCase()), lectura));
}

// -- pasos de la normalizacion --------------------------------------------

function fold(s: string): string {
  let out = "";
  for (const ch of s) {
    // Las marcas combinantes se DESCARTAN, no se traducen. Ver el comentario
    // gemelo en `moderation_filter.dart`: el mapa solo cubre precompuestos, y
    // el texto descompuesto conservaba la marca, que partia el token en dos.
    if (isCombining(ch.codePointAt(0) ?? 0)) continue;
    out += VETTED_FOLD[ch] ?? ch;
  }
  return out;
}

function isCombining(cp: number): boolean {
  for (let i = 0; i < VETTED_COMBINING_RANGES.length; i += 2) {
    if (cp < VETTED_COMBINING_RANGES[i]) return false;
    if (cp <= VETTED_COMBINING_RANGES[i + 1]) return true;
  }
  return false;
}

function leet(s: string, lectura: Lectura): string {
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
    // texto mas comun que existe, un insulto con signo de exclamacion. Las
    // otras lecturas —todas menos la estricta— los leen distinto, salvo la
    // `@` de un mail; ver `checkText`.
    const ambiguo =
      VETTED_LEET_ALSO_AT_EDGES.has(ch) && !esArrobaDeMail(chars, i);
    if (ambiguo && lectura === "total") {
      out += rep;
    } else if (ambiguo && lectura !== "estricta") {
      out += seLeeComoLetra(chars, i, lectura) ? rep : ch;
    } else if (VETTED_LEET_ONLY_BETWEEN_LETTERS.has(ch)) {
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

/**
 * Si la `@` en `i` es la de un mail: le sigue un dominio (`gmail.com`). ESPEJO
 * de `_esArrobaDeMail` en `moderation_filter.dart`: esa `@` no se relee, va
 * con la regla estricta en todas las lecturas (`cul!@r.com` leia `culiar`).
 */
function esArrobaDeMail(chars: readonly string[], i: number): boolean {
  if (chars[i] !== "@") return false;
  // Un mail tiene usuario: algo pegado antes de la `@`, con al menos una
  // letra o digito. Sin esto una MENCION con puntos pasaba por mail, y
  // `@ndate.a.morir` dejaba de cazarse.
  let k = i - 1;
  let hayUsuario = false;
  while (
    k >= 0 &&
    (isAlnum(chars[k]) || "._-+".includes(chars[k]) ||
      VETTED_LEET_ALSO_AT_EDGES.has(chars[k]))
  ) {
    hayUsuario = hayUsuario || isAlnum(chars[k]);
    k--;
  }
  if (!hayUsuario) return false;
  let j = i + 1;
  while (
    j < chars.length &&
    (isAlnum(chars[j]) || chars[j] === "-" || chars[j] === "_")
  ) {
    j++;
  }
  return j > i + 1 && j + 1 < chars.length && chars[j] === "." &&
    isAlnum(chars[j + 1]);
}

/**
 * Si la corrida de simbolos de `VETTED_LEET_ALSO_AT_EDGES` que contiene a `i`
 * tiene una letra o un digito en cada extremo. ESPEJO de `_corridaInterna` en
 * `moderation_filter.dart`.
 */
function corridaInterna(chars: readonly string[], i: number): boolean {
  let desde = i;
  while (desde > 0 && VETTED_LEET_ALSO_AT_EDGES.has(chars[desde - 1])) desde--;
  let hasta = i;
  while (hasta < chars.length && VETTED_LEET_ALSO_AT_EDGES.has(chars[hasta])) {
    hasta++;
  }
  return desde > 0 && isAlnum(chars[desde - 1]) &&
    hasta < chars.length && isAlnum(chars[hasta]);
}

/**
 * En las lecturas prefijo, sufijo y adyacente, si el simbolo en `i` se
 * traduce. ESPEJO de `_seLeeComoLetra` en `moderation_filter.dart`: cada
 * lectura traduce el borde de la palabra que le toca —`despues` es el de
 * adelante, `antes` el de atras— y deja el otro como adorno; si no toca
 * ninguna letra, solo el PRIMERO de una corrida que no toca nada.
 */
function seLeeComoLetra(
  chars: readonly string[],
  i: number,
  lectura: Lectura,
): boolean {
  const antes = i > 0 && isAlnum(chars[i - 1]);
  const despues = i + 1 < chars.length && isAlnum(chars[i + 1]);
  // Una corrida con letra en los DOS extremos esta ADENTRO de una palabra:
  // todos sus simbolos son letras (`cul!@r` es `culiar`).
  if (corridaInterna(chars, i)) return true;
  if (antes || despues) {
    if (lectura === "prefijo") return despues;
    if (lectura === "sufijo") return antes;
    return true;
  }
  if (i > 0 && VETTED_LEET_ALSO_AT_EDGES.has(chars[i - 1])) return false;
  let j = i;
  while (j < chars.length && VETTED_LEET_ALSO_AT_EDGES.has(chars[j])) j++;
  return j === chars.length || !isAlnum(chars[j]);
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
 *    token, despues de sacarle las palabras de `VETTED_ALLOWLIST`.
 *
 * Lo que no hace es pegar el texto entero. Esa version —la obvia— bloquea
 * `otro loco`, porque `otroloco` contiene `trolo`. Tambien `otro lote`. Los
 * dos son castellano rioplatense corriente y los dos estan en el corpus.
 */
function evades(tokens: readonly string[]): boolean {
  const candidatos: string[] = [];
  let corrida: string[] = [];

  const cerrarCorrida = (): void => {
    if (corrida.length > 1) candidatos.push(corrida.join(""));
    corrida = [];
  };

  for (const t of tokens) {
    // Se pega con el anterior solo si LOS DOS son cortos. Ver el comentario
    // gemelo en `moderation_filter.dart`: con la regla vieja —corridas de UN
    // caracter— `pu-to` y `p-uto` salteaban la capa entera.
    const corto = t.length <= VETTED_JOIN_MAX_FRAGMENT;
    const anteriorCorto =
      corrida.length > 0 &&
      corrida[corrida.length - 1].length <= VETTED_JOIN_MAX_FRAGMENT;

    if (corto && (corrida.length === 0 || anteriorCorto)) {
      corrida.push(t);
      continue;
    }
    cerrarCorrida();
    candidatos.push(t);
    if (corto) corrida.push(t);
  }
  cerrarCorrida();

  for (const c of candidatos) {
    for (const pedazo of sinAllowlist(c)) {
      for (const termino of VETTED_ANTI_EVASION) {
        if (pedazo.includes(termino)) return true;
      }
    }
  }
  return false;
}

/**
 * `candidato` partido en lo que queda al sacarle, de ADENTRO, cada palabra de
 * `VETTED_ALLOWLIST`. ESPEJO de `_sinAllowlist` en `moderation_filter.dart`:
 * un mail o una mencion pegan la palabra con lo de al lado
 * (`juan@computo.com` da `juanacomputo`), y saltear solo el token exacto
 * dejaba que el `puto` de adentro bloqueara una direccion valida.
 */
function sinAllowlist(candidato: string): string[] {
  let pedazos = [candidato];
  for (const palabra of VETTED_ALLOWLIST) {
    pedazos = pedazos.flatMap((p) => p.split(palabra));
  }
  return pedazos.filter((p) => p.length > 0);
}

/**
 * Las frases vetadas sin espacios: `hijo de puta` -> `hijodeputa`. Es la forma
 * en que quedan cuando se escriben con todas las letras separadas.
 */
const COMPACT_BLOCK_PHRASES = VETTED_BLOCK_PHRASES.map((p) => p.join(""));
const COMPACT_REVIEW_PHRASES = VETTED_REVIEW_PHRASES.map((p) => p.join(""));

/**
 * La pasada de las letras sueltas. ESPEJO de `_spelledOut` en
 * `moderation_filter.dart` — ver ahi el porque completo.
 *
 * Corta: `p-i-j-a` da puros tokens de UNA letra; la pasada B los pega pero
 * solo los compara contra `VETTED_ANTI_EVASION`, que no tiene `pija` ni
 * `culo` a proposito. Aca se compara contra la lista COMPLETA, por subcadena,
 * pero solo sobre corridas de tokens de un caracter — el castellano no produce
 * esas corridas, asi que la subcadena no choca con palabras legitimas. No se
 * extiende a fragmentos de dos o tres letras: `por no` pegado da `porno`.
 */
function spelledOut(tokens: readonly string[]): ModerationVerdict | null {
  const corridas: string[] = [];
  let actual = "";
  let largo = 0;

  const cerrar = (): void => {
    if (largo > 1) corridas.push(actual);
    actual = "";
    largo = 0;
  };

  for (const t of tokens) {
    if (t.length === 1) {
      actual += t;
      largo++;
    } else {
      cerrar();
    }
  }
  cerrar();
  if (corridas.length === 0) return null;

  const contiene = (terminos: Iterable<string>): boolean => {
    for (const termino of terminos) {
      if (corridas.some((c) => c.includes(termino))) return true;
    }
    return false;
  };

  if (contiene(VETTED_BLOCK_WORDS) || contiene(COMPACT_BLOCK_PHRASES)) {
    return "block";
  }
  if (contiene(VETTED_REVIEW_WORDS) || contiene(COMPACT_REVIEW_PHRASES)) {
    return "review";
  }
  return null;
}
