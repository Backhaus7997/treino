// GENERADO POR scripts/build_moderation_list.py — NO EDITAR A MANO.
//
// Fuente: assets/moderation/terminos-vetados.json
// El espejo de este archivo es lib/core/moderation/vetted_terms.g.dart, y sale
// del MISMO origen en la misma corrida.

/** Version del corpus. Sube cuando cambia la lista. */
export const VETTED_TERMS_VERSION = 1;

/**
 * `á` -> `a`, `ñ` -> `n`. Sale de `unicodedata` de Python, no de una tabla
 * escrita a mano: ni Dart ni TypeScript traen NFD en su biblioteca estandar,
 * y dos tablas a mano divergen en la tercera vocal rara.
 */
export const VETTED_FOLD: Readonly<Record<string, string>> = {"à": "a", "á": "a", "â": "a", "ã": "a", "ä": "a", "å": "a", "ç": "c", "è": "e", "é": "e", "ê": "e", "ë": "e", "ì": "i", "í": "i", "î": "i", "ï": "i", "ñ": "n", "ò": "o", "ó": "o", "ô": "o", "õ": "o", "ö": "o", "ù": "u", "ú": "u", "û": "u", "ü": "u", "ý": "y", "ÿ": "y", "ā": "a", "ă": "a", "ą": "a", "ć": "c", "ĉ": "c", "ċ": "c", "č": "c", "ď": "d", "ē": "e", "ĕ": "e", "ė": "e", "ę": "e", "ě": "e", "ĝ": "g", "ğ": "g", "ġ": "g", "ģ": "g", "ĥ": "h", "ĩ": "i", "ī": "i", "ĭ": "i", "į": "i", "ĵ": "j", "ķ": "k", "ĺ": "l", "ļ": "l", "ľ": "l", "ń": "n", "ņ": "n", "ň": "n", "ō": "o", "ŏ": "o", "ő": "o", "ŕ": "r", "ŗ": "r", "ř": "r", "ś": "s", "ŝ": "s", "ş": "s", "š": "s", "ţ": "t", "ť": "t", "ũ": "u", "ū": "u", "ŭ": "u", "ů": "u", "ű": "u", "ų": "u", "ŵ": "w", "ŷ": "y", "ź": "z", "ż": "z", "ž": "z", "ơ": "o", "ư": "u", "ǎ": "a", "ǐ": "i", "ǒ": "o", "ǔ": "u", "ǖ": "u", "ǘ": "u", "ǚ": "u", "ǜ": "u", "ǟ": "a", "ǡ": "a", "ǧ": "g", "ǩ": "k", "ǫ": "o", "ǭ": "o", "ǰ": "j", "ǵ": "g", "ǹ": "n", "ǻ": "a", "ȁ": "a", "ȃ": "a", "ȅ": "e", "ȇ": "e", "ȉ": "i", "ȋ": "i", "ȍ": "o", "ȏ": "o", "ȑ": "r", "ȓ": "r", "ȕ": "u", "ȗ": "u", "ș": "s", "ț": "t", "ȟ": "h", "ȧ": "a", "ȩ": "e", "ȫ": "o", "ȭ": "o", "ȯ": "o", "ȱ": "o", "ȳ": "y"};

/** Deshacer leet: `0` -> `o`, `@` -> `a`. */
export const VETTED_LEET: Readonly<Record<string, string>> = {"!": "i", "$": "s", "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a"};

/**
 * Los simbolos de `VETTED_LEET` que SOLO se traducen con letra a los dos
 * lados. Sin esa regla `puta!` normaliza a `putai` y deja de matchear.
 */
export const VETTED_LEET_ONLY_BETWEEN_LETTERS: ReadonlySet<string> = new Set(["!", "$", "@"]);

/**
 * Runs de este largo o mas colapsan a un caracter: `putooooo` -> `puto`.
 * Tres y no dos: el castellano tiene dobles (`carro`, `perro`) pero no
 * triples.
 */
export const VETTED_COLLAPSE_MIN = 3;

/** Terminos de severidad `block` de UNA palabra, ya normalizados. */
export const VETTED_BLOCK_WORDS: ReadonlySet<string> = new Set(["chupapija", "chupapijas", "cojer", "concha", "conchas", "conchuda", "conchudo", "culiar", "garcha", "garchame", "garchar", "hdp", "koncha", "kulo", "lctm", "marica", "maricon", "maricones", "matate", "mogolica", "mogolico", "mogolicos", "pedofila", "pedofilia", "pedofilo", "pija", "pijas", "pornhub", "porno", "pornografia", "puta", "putas", "putazo", "putito", "puto", "putos", "pvta", "pvtas", "pvto", "pvtos", "sidoso", "subnormal", "suicidate", "tortillera", "travuco", "trolo", "trolos", "verga", "vergas", "zoofilia"]);

/** Terminos de severidad `block` de VARIAS palabras, como secuencia de tokens. */
export const VETTED_BLOCK_PHRASES: readonly (readonly string[])[] = [["andate", "a", "la", "concha"], ["andate", "a", "morir"], ["chupame", "la", "pija"], ["colgate", "de", "un", "arbol"], ["gorda", "de", "mierda"], ["gordo", "de", "mierda"], ["hija", "de", "puta"], ["hijo", "de", "puta"], ["hijos", "de", "puta"], ["la", "concha", "de", "su", "madre"], ["la", "concha", "de", "tu", "madre"], ["muerta", "de", "hambre"], ["muerto", "de", "hambre"], ["negra", "de", "mierda"], ["negro", "de", "mierda"], ["ojala", "te", "mueras"], ["retrasado", "mental"], ["te", "reviento"], ["te", "voy", "a", "cagar", "a", "trompadas"], ["te", "voy", "a", "matar"], ["te", "voy", "a", "reventar"], ["vaca", "de", "mierda"]];

/** Terminos de severidad `review` de UNA palabra. */
export const VETTED_REVIEW_WORDS: ReadonlySet<string> = new Set(["coger", "cogerte", "culo", "culos", "estupida", "estupido", "forra", "forro", "gil", "gila", "idiota", "imbecil", "pelotuda", "pelotudas", "pelotudo", "pelotudos", "proana", "promia", "sorete", "tarada", "tarado", "tetas", "thinspiration", "thinspo"]);

/** Terminos de severidad `review` de VARIAS palabras. */
export const VETTED_REVIEW_PHRASES: readonly (readonly string[])[] = [["dejar", "de", "comer", "para"], ["manga", "de", "inutiles"], ["pro", "ana"], ["vomitar", "despues", "de", "comer"]];

/**
 * Subconjunto para la pasada antievasion: subcadena sobre el texto sin
 * separadores. Chico y de severidad alta a proposito — ver el JSON fuente.
 */
export const VETTED_ANTI_EVASION: readonly string[] = ["chupapija", "conchudo", "garchame", "garchar", "maricon", "mogolico", "pedofilia", "pedofilo", "pornhub", "putazo", "puto", "sidoso", "tortillera", "travuco", "trolo", "zoofilia"];

/**
 * Palabras legitimas que contienen un termino de `VETTED_ANTI_EVASION`. Se
 * sacan del texto antes de la pasada B.
 */
export const VETTED_ALLOWLIST: ReadonlySet<string> = new Set(["amputo", "computo", "computos", "controlo", "descontrolo", "disputo", "imputo", "reputo"]);

/**
 * Corpus de conformidad. La suite de Dart corre EXACTAMENTE estos mismos
 * casos: si los dos veredictos no coinciden, una de las dos se pone roja.
 * Ninguna de las dos escribe sus expectativas a mano.
 */
export const VETTED_CASES: readonly { texto: string; espera: string; por: string }[] = [
  { texto: "computadora", espera: "ok", por: "contiene `puta`" },
  { texto: "me lo anote en la computadora", espera: "ok", por: "contiene `puta`" },
  { texto: "calculo", espera: "ok", por: "contiene `culo`" },
  { texto: "cálculo", espera: "ok", por: "contiene `culo`, con acento" },
  { texto: "disputa", espera: "ok", por: "contiene `puta`" },
  { texto: "reputación", espera: "ok", por: "contiene `puta`" },
  { texto: "sexteto", espera: "ok", por: "contiene `sex`" },
  { texto: "escocia", espera: "ok", por: "falso positivo clasico" },
  { texto: "cuatro series para el musculo dorsal", espera: "ok", por: "`musculo` contiene `culo`: el caso de ESTE producto" },
  { texto: "trabajo de musculacion tres veces por semana", espera: "ok", por: "vocabulario central de la app" },
  { texto: "el computo de las series", espera: "ok", por: "contiene `puto` — el que obliga a la allowlist" },
  { texto: "me puse el pijama", espera: "ok", por: "contiene `pija`" },
  { texto: "el diputado Vergara", espera: "ok", por: "contiene `puta` y `verga`" },
  { texto: "hoy entrené piernas y me fue bien", espera: "ok", por: "control: texto normal pasa" },
  { texto: "puto", espera: "block", por: "termino directo" },
  { texto: "PUTO", espera: "block", por: "mayusculas" },
  { texto: "pÚtO", espera: "block", por: "mayusculas mezcladas y acento" },
  { texto: "putooooo", espera: "block", por: "caracteres repetidos" },
  { texto: "p u t o", espera: "block", por: "separado por espacios" },
  { texto: "p-u-t-o", espera: "block", por: "separado por guiones" },
  { texto: "p.u.t.o", espera: "block", por: "separado por puntos" },
  { texto: "pvto", espera: "block", por: "v por u" },
  { texto: "sos un hijo de puta", espera: "block", por: "frase de varias palabras" },
  { texto: "hijo  de   PUTA", espera: "block", por: "frase con espacios de mas" },
  { texto: "te voy a matar", espera: "block", por: "amenaza" },
  { texto: "and4te a morir", espera: "block", por: "leet: 4 -> a" },
  { texto: "sos un pelotudo", espera: "review", por: "insulto casual rioplatense" },
  { texto: "que gil", espera: "review", por: "insulto leve" },
  { texto: "thinspo", espera: "review", por: "contenido pro trastorno alimentario" },
  { texto: "cuantos años entrenas por semana", espera: "ok", por: "`ñ` pliega a `n`: `años` -> `anos`. Vigila que nadie meta `ano` en la lista" },
  { texto: "hace 3 años que entreno", espera: "ok", por: "leet `3`->`e` sobre un numero real, mas el plegado de la ñ" },
  { texto: "sos un puta!", espera: "block", por: "el `!` final NO se traduce a `i`: si se tradujera, `putai` no matchearia" },
  { texto: "10x3 con 90 segundos de pausa", espera: "ok", por: "notacion de series: los digitos pasan por leet y no pueden inventar un veto" },
  { texto: "otro loco que entrena a las 6", espera: "ok", por: "pegado entero daria `otroloco` -> contiene `trolo`. La pasada B NO pega entre palabras" },
  { texto: "traeme otro lote de bandas", espera: "ok", por: "mismo caso: `otrolote` contiene `trolo`" },
  { texto: "pvto", espera: "block", por: "grafia de evasion explicita, no transformacion" },
  { texto: "holaputo", espera: "block", por: "pegado adentro de un token: la pasada B busca subcadena por token" },
  { texto: "no me controlo con la comida", espera: "ok", por: "`controlo` contiene `trolo` y esta en la allowlist" },
];
