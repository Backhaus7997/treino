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
export const VETTED_FOLD: Readonly<Record<string, string>> = {"à": "a", "á": "a", "â": "a", "ã": "a", "ä": "a", "å": "a", "ç": "c", "è": "e", "é": "e", "ê": "e", "ë": "e", "ì": "i", "í": "i", "î": "i", "ï": "i", "ñ": "n", "ò": "o", "ó": "o", "ô": "o", "õ": "o", "ö": "o", "ù": "u", "ú": "u", "û": "u", "ü": "u", "ý": "y", "ÿ": "y", "ā": "a", "ă": "a", "ą": "a", "ć": "c", "ĉ": "c", "ċ": "c", "č": "c", "ď": "d", "ē": "e", "ĕ": "e", "ė": "e", "ę": "e", "ě": "e", "ĝ": "g", "ğ": "g", "ġ": "g", "ģ": "g", "ĥ": "h", "ĩ": "i", "ī": "i", "ĭ": "i", "į": "i", "ĵ": "j", "ķ": "k", "ĺ": "l", "ļ": "l", "ľ": "l", "ń": "n", "ņ": "n", "ň": "n", "ō": "o", "ŏ": "o", "ő": "o", "ŕ": "r", "ŗ": "r", "ř": "r", "ś": "s", "ŝ": "s", "ş": "s", "š": "s", "ţ": "t", "ť": "t", "ũ": "u", "ū": "u", "ŭ": "u", "ů": "u", "ű": "u", "ų": "u", "ŵ": "w", "ŷ": "y", "ź": "z", "ż": "z", "ž": "z"};

/** Deshacer leet: `0` -> `o`, `@` -> `a`. */
export const VETTED_LEET: Readonly<Record<string, string>> = {"!": "i", "$": "s", "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a"};

/**
 * Los simbolos de `VETTED_LEET` que SOLO se traducen con letra a los dos
 * lados. Sin esa regla `puta!` normaliza a `putai` y deja de matchear.
 */
export const VETTED_LEET_ONLY_BETWEEN_LETTERS: ReadonlySet<string> = new Set(["!", "$", "@"]);

/**
 * Los simbolos que el filtro vuelve a leer sin la regla de
 * `VETTED_LEET_ONLY_BETWEEN_LETTERS`, en todas las lecturas menos la estricta
 * (la `@` de un mail no se relee nunca). Gana el peor veredicto de todas:
 * `put@` necesita la `@` como `a`; `pija@`, como adorno. Ver
 * `LEET_TAMBIEN_EN_BORDES` en scripts/build_moderation_list.py.
 */
export const VETTED_LEET_ALSO_AT_EDGES: ReadonlySet<string> = new Set(["!", "$", "@"]);

/**
 * Runs de este largo o mas colapsan a un caracter: `putooooo` -> `puto`.
 * Tres y no dos: el castellano tiene dobles (`carro`, `perro`) pero no
 * triples.
 */
export const VETTED_COLLAPSE_MIN = 3;

/**
 * Largo maximo de un fragmento para que la pasada antievasion lo PEGUE con el
 * de al lado. Ver el porque en scripts/build_moderation_list.py.
 */
export const VETTED_JOIN_MAX_FRAGMENT = 3;

/**
 * Rangos `[desde, hasta]` de marcas combinantes (categoria Unicode `Mn`),
 * aplanados. Se descartan antes de tokenizar: sin esto el mismo texto llega
 * descompuesto —`u` + U+0301 en vez de `ú`—, la marca parte el token en dos y
 * el termino no matchea, mientras que la forma precompuesta si se bloquea.
 */
export const VETTED_COMBINING_RANGES: readonly number[] = [0x0300, 0x036F, 0x1AB0, 0x1AFF, 0x1DC0, 0x1DFF, 0x20D0, 0x20FF, 0xFE20, 0xFE2F];

/** Terminos de severidad `block` de UNA palabra, ya normalizados. */
export const VETTED_BLOCK_WORDS: ReadonlySet<string> = new Set(["chupapija", "chupapijas", "cojer", "concha", "conchas", "conchuda", "conchudo", "culiar", "garcha", "garchame", "garchar", "hdp", "koncha", "kulo", "lctm", "marica", "maricon", "maricones", "mogolica", "mogolico", "mogolicos", "pedofila", "pedofilia", "pedofilo", "pija", "pijas", "pornhub", "porno", "pornografia", "puta", "putas", "putazo", "putito", "puto", "putos", "pvta", "pvtas", "pvto", "pvtos", "sidoso", "subnormal", "suicidate", "tortillera", "travuco", "trolo", "trolos", "verga", "vergas", "zoofilia"]);

/** Terminos de severidad `block` de VARIAS palabras, como secuencia de tokens. */
export const VETTED_BLOCK_PHRASES: readonly (readonly string[])[] = [["andate", "a", "la", "concha"], ["andate", "a", "morir"], ["chupame", "la", "pija"], ["colgate", "de", "un", "arbol"], ["gorda", "de", "mierda"], ["gordo", "de", "mierda"], ["hija", "de", "puta"], ["hijo", "de", "puta"], ["hijos", "de", "puta"], ["la", "concha", "de", "su", "madre"], ["la", "concha", "de", "tu", "madre"], ["muerta", "de", "hambre"], ["muerto", "de", "hambre"], ["negra", "de", "mierda"], ["negro", "de", "mierda"], ["ojala", "te", "mueras"], ["retrasado", "mental"], ["te", "reviento"], ["te", "voy", "a", "cagar", "a", "trompadas"], ["te", "voy", "a", "matar"], ["te", "voy", "a", "reventar"], ["vaca", "de", "mierda"]];

/** Terminos de severidad `review` de UNA palabra. */
export const VETTED_REVIEW_WORDS: ReadonlySet<string> = new Set(["coger", "cogerte", "culo", "culos", "estupida", "estupido", "forra", "forro", "gil", "gila", "idiota", "imbecil", "matate", "pelotuda", "pelotudas", "pelotudo", "pelotudos", "proana", "promia", "sorete", "tarada", "tarado", "tetas", "thinspiration", "thinspo"]);

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
export const VETTED_CASES: readonly {
  texto: string;
  espera: string;
  normalizado: string;
  lecturas: readonly string[];
  por: string;
}[] = [
  { texto: "computadora", espera: "ok", normalizado: "computadora", lecturas: ["computadora"], por: "contiene `puta`" },
  { texto: "me lo anote en la computadora", espera: "ok", normalizado: "me lo anote en la computadora", lecturas: ["me lo anote en la computadora"], por: "contiene `puta`" },
  { texto: "calculo", espera: "ok", normalizado: "calculo", lecturas: ["calculo"], por: "contiene `culo`" },
  { texto: "cálculo", espera: "ok", normalizado: "calculo", lecturas: ["calculo"], por: "contiene `culo`, con acento" },
  { texto: "disputa", espera: "ok", normalizado: "disputa", lecturas: ["disputa"], por: "contiene `puta`" },
  { texto: "reputación", espera: "ok", normalizado: "reputacion", lecturas: ["reputacion"], por: "contiene `puta`" },
  { texto: "sexteto", espera: "ok", normalizado: "sexteto", lecturas: ["sexteto"], por: "contiene `sex`" },
  { texto: "escocia", espera: "ok", normalizado: "escocia", lecturas: ["escocia"], por: "falso positivo clasico" },
  { texto: "cuatro series para el musculo dorsal", espera: "ok", normalizado: "cuatro series para el musculo dorsal", lecturas: ["cuatro series para el musculo dorsal"], por: "`musculo` contiene `culo`: el caso de ESTE producto" },
  { texto: "trabajo de musculacion tres veces por semana", espera: "ok", normalizado: "trabajo de musculacion tres veces por semana", lecturas: ["trabajo de musculacion tres veces por semana"], por: "vocabulario central de la app" },
  { texto: "el computo de las series", espera: "ok", normalizado: "el computo de las series", lecturas: ["el computo de las series"], por: "contiene `puto` — el que obliga a la allowlist" },
  { texto: "me puse el pijama", espera: "ok", normalizado: "me puse el pijama", lecturas: ["me puse el pijama"], por: "contiene `pija`" },
  { texto: "el diputado Vergara", espera: "ok", normalizado: "el diputado vergara", lecturas: ["el diputado vergara"], por: "contiene `puta` y `verga`" },
  { texto: "hoy entrené piernas y me fue bien", espera: "ok", normalizado: "hoy entrene piernas y me fue bien", lecturas: ["hoy entrene piernas y me fue bien"], por: "control: texto normal pasa" },
  { texto: "puto", espera: "block", normalizado: "puto", lecturas: ["puto"], por: "termino directo" },
  { texto: "PUTO", espera: "block", normalizado: "puto", lecturas: ["puto"], por: "mayusculas" },
  { texto: "pÚtO", espera: "block", normalizado: "puto", lecturas: ["puto"], por: "mayusculas mezcladas y acento" },
  { texto: "putooooo", espera: "block", normalizado: "puto", lecturas: ["puto"], por: "caracteres repetidos" },
  { texto: "p u t o", espera: "block", normalizado: "p u t o", lecturas: ["p u t o"], por: "separado por espacios" },
  { texto: "p-u-t-o", espera: "block", normalizado: "p-u-t-o", lecturas: ["p-u-t-o"], por: "separado por guiones" },
  { texto: "p.u.t.o", espera: "block", normalizado: "p.u.t.o", lecturas: ["p.u.t.o"], por: "separado por puntos" },
  { texto: "pvto", espera: "block", normalizado: "pvto", lecturas: ["pvto"], por: "v por u" },
  { texto: "sos un hijo de puta", espera: "block", normalizado: "sos un hijo de puta", lecturas: ["sos un hijo de puta"], por: "frase de varias palabras" },
  { texto: "hijo  de   PUTA", espera: "block", normalizado: "hijo  de puta", lecturas: ["hijo  de puta"], por: "frase con espacios de mas" },
  { texto: "te voy a matar", espera: "block", normalizado: "te voy a matar", lecturas: ["te voy a matar"], por: "amenaza" },
  { texto: "and4te a morir", espera: "block", normalizado: "andate a morir", lecturas: ["andate a morir"], por: "leet: 4 -> a" },
  { texto: "sos un pelotudo", espera: "review", normalizado: "sos un pelotudo", lecturas: ["sos un pelotudo"], por: "insulto casual rioplatense" },
  { texto: "que gil", espera: "review", normalizado: "que gil", lecturas: ["que gil"], por: "insulto leve" },
  { texto: "thinspo", espera: "review", normalizado: "thinspo", lecturas: ["thinspo"], por: "contenido pro trastorno alimentario" },
  { texto: "cuantos años entrenas por semana", espera: "ok", normalizado: "cuantos anos entrenas por semana", lecturas: ["cuantos anos entrenas por semana"], por: "`ñ` pliega a `n`: `años` -> `anos`. Vigila que nadie meta `ano` en la lista" },
  { texto: "hace 3 años que entreno", espera: "ok", normalizado: "hace e anos que entreno", lecturas: ["hace e anos que entreno"], por: "leet `3`->`e` sobre un numero real, mas el plegado de la ñ" },
  { texto: "sos un puta!", espera: "block", normalizado: "sos un puta!", lecturas: ["sos un puta!", "sos un putai"], por: "el `!` final NO se traduce a `i`: si se tradujera, `putai` no matchearia" },
  { texto: "10x3 con 90 segundos de pausa", espera: "ok", normalizado: "ioxe con 9o segundos de pausa", lecturas: ["ioxe con 9o segundos de pausa"], por: "notacion de series: los digitos pasan por leet y no pueden inventar un veto" },
  { texto: "otro loco que entrena a las 6", espera: "ok", normalizado: "otro loco que entrena a las 6", lecturas: ["otro loco que entrena a las 6"], por: "pegado entero daria `otroloco` -> contiene `trolo`. La pasada B NO pega entre palabras" },
  { texto: "traeme otro lote de bandas", espera: "ok", normalizado: "traeme otro lote de bandas", lecturas: ["traeme otro lote de bandas"], por: "mismo caso: `otrolote` contiene `trolo`" },
  { texto: "pvto", espera: "block", normalizado: "pvto", lecturas: ["pvto"], por: "grafia de evasion explicita, no transformacion" },
  { texto: "holaputo", espera: "block", normalizado: "holaputo", lecturas: ["holaputo"], por: "pegado adentro de un token: la pasada B busca subcadena por token" },
  { texto: "no me controlo con la comida", espera: "ok", normalizado: "no me controlo con la comida", lecturas: ["no me controlo con la comida"], por: "`controlo` contiene `trolo` y esta en la allowlist" },
  { texto: "hice press banca con barra", espera: "ok", normalizado: "hice press banca con barra", lecturas: ["hice press banca con barra"], por: "dobles `ss` y `rr`: el colapso arranca en TRES, no en dos" },
  { texto: "el perro del gimnasio se llama Rocco", espera: "ok", normalizado: "el perro del gimnasio se llama rocco", lecturas: ["el perro del gimnasio se llama rocco"], por: "tres dobles seguidas — `rr`, `ll`, `cc`" },
  { texto: "acción correcta en el banco", espera: "ok", normalizado: "accion correcta en el banco", lecturas: ["accion correcta en el banco"], por: "doble con acento arriba: plegado y colapso se tocan" },
  { texto: "pu-to", espera: "block", normalizado: "pu-to", lecturas: ["pu-to"], por: "fragmentos de 2 y 2. Con la regla vieja —corridas de UN caracter— un separador salteaba la capa entera" },
  { texto: "p-uto", espera: "block", normalizado: "p-uto", lecturas: ["p-uto"], por: "fragmentos de 1 y 3" },
  { texto: "pu to", espera: "block", normalizado: "pu to", lecturas: ["pu to"], por: "mismo caso, separado por espacio" },
  { texto: "púto", espera: "block", normalizado: "puto", lecturas: ["puto"], por: "`u` + U+0301 descompuesto: se ve identico a `púto` y antes pasaba, porque la marca partia el token en dos" },
  { texto: "mogólico", espera: "block", normalizado: "mogolico", lecturas: ["mogolico"], por: "misma descomposicion sobre otro termino" },
  { texto: "otro lo hizo mejor", espera: "ok", normalizado: "otro lo hizo mejor", lecturas: ["otro lo hizo mejor"], por: "`otro`+`lo` pegados dan `otrolo`, que contiene `trolo`. La regla pide que los DOS fragmentos sean cortos, y `otro` no lo es" },
  { texto: "dale que va", espera: "ok", normalizado: "dale que va", lecturas: ["dale que va"], por: "tres fragmentos cortos seguidos se pegan: `dalequeva` no contiene nada, y tiene que seguir siendo asi" },
  { texto: "con-chudo", espera: "ok", normalizado: "con-chudo", lecturas: ["con-chudo"], por: "HUECO CONOCIDO, fijado a proposito. `con`(3) y `chudo`(5): la regla no los pega porque el segundo es largo. Pegarlos igual reintroduce el falso positivo sobre `otro lo`, y un filtro que bloquea castellano corriente dura una semana. El backstop de este caso es la cola de reportes, no la lista" },
  { texto: "p i j a", espera: "block", normalizado: "p i j a", lecturas: ["p i j a"], por: "letras sueltas de un termino FUERA de `antievasion`: la pasada B lo pegaba y no tenia contra que compararlo. Lo caza la pasada C" },
  { texto: "p-i-j-a", espera: "block", normalizado: "p-i-j-a", lecturas: ["p-i-j-a"], por: "pasada C, separado por guiones" },
  { texto: "p.i.j.a", espera: "block", normalizado: "p.i.j.a", lecturas: ["p.i.j.a"], por: "pasada C, separado por puntos" },
  { texto: "h.i.j.o d.e p.u.t.a", espera: "block", normalizado: "h.i.j.o d.e p.u.t.a", lecturas: ["h.i.j.o d.e p.u.t.a"], por: "frase deletreada entera: la pasada C compara contra las frases sin espacios (`hijodeputa`)" },
  { texto: "y p u t a", espera: "block", normalizado: "y p u t a", lecturas: ["y p u t a"], por: "una letra legitima pegada adelante no la salva: la pasada C compara por subcadena dentro de la corrida" },
  { texto: "c u l o", espera: "review", normalizado: "c u l o", lecturas: ["c u l o"], por: "la pasada C respeta la severidad del termino: `culo` es `review` escrito normal y deletreado" },
  { texto: "por no entrenar", espera: "ok", normalizado: "por no entrenar", lecturas: ["por no entrenar"], por: "`por`+`no` pegados dan `porno`. La pasada C pega SOLO tokens de una letra por esto" },
  { texto: "hice 5 x 5 de sentadilla y 3 x 8 de press", espera: "ok", normalizado: "hice s x s de sentadilla y e x 8 de press", lecturas: ["hice s x s de sentadilla y e x 8 de press"], por: "la notacion de series produce letras sueltas legitimas (`s x s`, `y e x 8`): la corrida no contiene ningun termino" },
  { texto: "put@", espera: "block", normalizado: "put@", lecturas: ["put@", "puta"], por: "`@` al final de palabra. Con solo la lectura estricta —`@` solo entre letras— la forma mas natural del leet femenino pasaba entera. La caza la lectura sufijo" },
  { texto: "@ndate a morir", espera: "block", normalizado: "@ndate a morir", lecturas: ["@ndate a morir", "andate a morir"], por: "`@` al principio de palabra, sin ningun otro termino en la frase que la delate" },
  { texto: "te voy @ matar", espera: "block", normalizado: "te voy @ matar", lecturas: ["te voy @ matar", "te voy a matar"], por: "`@` suelta como preposicion: sin traducirla la frase pierde su `a` y no matchea" },
  { texto: "p1j@", espera: "block", normalizado: "pij@", lecturas: ["pij@", "pija"], por: "digito y `@` final en el mismo termino" },
  { texto: "pija@", espera: "block", normalizado: "pija@", lecturas: ["pija@", "pijaa"], por: "`@` DECORATIVA pegada a un termino completo. Traducida queda `pijaa`: por eso la forma estricta se evalua igual, y gana el peor veredicto" },
  { texto: "@pija", espera: "block", normalizado: "@pija", lecturas: ["@pija", "apija"], por: "`@` decorativa adelante: traducida queda `apija`" },
  { texto: "puta@", espera: "block", normalizado: "puta@", lecturas: ["puta@", "putaa"], por: "mismo caso con otro termino" },
  { texto: "culo@", espera: "review", normalizado: "culo@", lecturas: ["culo@", "culoa"], por: "la `@` decorativa tampoco puede bajarle la severidad a un `review`" },
  { texto: "@lucas nos vemos el lunes", espera: "ok", normalizado: "@lucas nos vemos el lunes", lecturas: ["@lucas nos vemos el lunes", "alucas nos vemos el lunes"], por: "una mencion: las lecturas amplias leen `alucas`, que no es nada" },
  { texto: "put@@", espera: "block", normalizado: "put@@", lecturas: ["put@@", "puta@", "putaa"], por: "sustitucion Y adorno juntos: la `@` pegada es la `a`, la de mas es adorno. Solo la lectura adyacente lo lee `puta`" },
  { texto: "put@!", espera: "block", normalizado: "put@!", lecturas: ["put@!", "puta!", "putai"], por: "la forma mas comun de lo anterior: leet con signo de exclamacion" },
  { texto: "@@ndate a morir", espera: "block", normalizado: "@@ndate a morir", lecturas: ["@@ndate a morir", "@andate a morir", "aandate a morir"], por: "lo mismo del lado de adelante: la `@` pegada a la `n` es la letra, la primera es adorno" },
  { texto: "pija@@", espera: "block", normalizado: "pija@@", lecturas: ["pija@@", "pijaa@", "pija"], por: "doble adorno sobre el termino completo: lo caza la lectura estricta" },
  { texto: "!diota", espera: "review", normalizado: "!diota", lecturas: ["!diota", "idiota"], por: "`!` por `i` al principio. La lectura estricta no lo traduce, porque el `!` pide letra a los dos lados" },
  { texto: "teta$$", espera: "review", normalizado: "teta$$", lecturas: ["teta$$", "tetas$", "tetass"], por: "`$` por `s` mas un adorno, sobre un termino `review`" },
  { texto: "$!do$o", espera: "block", normalizado: "$!doso", lecturas: ["$!doso", "$idoso", "sidoso"], por: "varias sustituciones seguidas: solo la lectura total las traduce todas" },
  { texto: "escribile a ana@controlo.com", espera: "ok", normalizado: "escribile a anaacontrolo.com", lecturas: ["escribile a anaacontrolo.com"], por: "la `@` de un mail pega el usuario con el dominio (`anacontrolo`). La allowlist se recorta de ADENTRO del token, no solo cuando es el token entero: antes esto daba `block` por el `trolo` de `controlo`" },
  { texto: "juan@computo.com", espera: "ok", normalizado: "juanacomputo.com", lecturas: ["juanacomputo.com"], por: "mismo caso, con el `puto` de `computo`" },
  { texto: "@computo", espera: "ok", normalizado: "@computo", lecturas: ["@computo", "acomputo"], por: "una mencion pegada a una palabra de la allowlist: la lectura adyacente lee `acomputo`" },
  { texto: "putocomputo", espera: "block", normalizado: "putocomputo", lecturas: ["putocomputo"], por: "recortar la allowlist de adentro no puede tapar lo que esta AFUERA de la palabra" },
  { texto: "computoputo", espera: "block", normalizado: "computoputo", lecturas: ["computoputo"], por: "lo mismo, del otro lado" },
  { texto: "cul!@r.com", espera: "ok", normalizado: "cul!@r.com", lecturas: ["cul!@r.com", "culi@r.com"], por: "un mail con `!` justo antes de la `@`: la lectura adyacente leia `culiar`, porque tomaba el `!` y la `@` como letras y pegaba usuario y dominio. La `@` de un mail —la que tiene un dominio despues— no se relee nunca" },
  { texto: "c0nch@s.com", espera: "block", normalizado: "conchas.com", lecturas: ["conchas.com"], por: "y eso no abre una evasion: la lectura estricta traduce la `@` entre letras desde siempre, asi que un termino con forma de mail se sigue cazando" },
  { texto: "@c0lg@t3 d3 un @rb0l", espera: "ok", normalizado: "@colgate de un @rbol", lecturas: ["@colgate de un @rbol", "acolgate de un arbol"], por: "HUECO CONOCIDO, fijado a proposito. La lectura de los simbolos se elige para TODO el texto, no palabra por palabra: la primera `@` es adorno en el borde de adelante de `colgate` y la de `@rbol` es letra en el mismo borde. Ninguna lectura acierta las dos. Elegir por palabra rompe el matcheo de frases, que compara tokens alineados. El backstop es la cola de reportes" },
  { texto: "tet@$!", espera: "ok", normalizado: "tet@$!", lecturas: ["tet@$!", "teta$!", "tetasi"], por: "HUECO CONOCIDO, fijado a proposito. Dos sustituciones seguidas en el borde (`@` por `a`, `$` por `s`) MAS un adorno (`!`): la lectura total traduce tambien el adorno y las de borde traducen solo el simbolo pegado a la letra. Mismo backstop" },
  { texto: "mandame el plan a juan@gmail.com", espera: "ok", normalizado: "mandame el plan a juanagmail.com", lecturas: ["mandame el plan a juanagmail.com"], por: "un mail comun. La `@` entre letras se traduce desde siempre y pega usuario y dominio en un token; ver el caso de `ana@controlo.com`" },
  { texto: "u$s 100 por mes", espera: "ok", normalizado: "uss ioo por mes", lecturas: ["uss ioo por mes"], por: "`$` entre letras, como se escribe el dolar en Argentina" },
];
