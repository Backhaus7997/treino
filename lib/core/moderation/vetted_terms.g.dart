// GENERADO POR scripts/build_moderation_list.py — NO EDITAR A MANO.
//
// Fuente: assets/moderation/terminos-vetados.json
// El espejo de este archivo es functions/src/moderation/vetted_terms.g.ts, y
// sale del MISMO origen en la misma corrida.
library;

/// Version del corpus. Sube cuando cambia la lista.
const int kVettedTermsVersion = 1;

/// `á` -> `a`, `ñ` -> `n`. Sale de `unicodedata` de Python, no de una tabla
/// escrita a mano: ni Dart ni TypeScript traen NFD en su biblioteca estandar,
/// y dos tablas a mano divergen en la tercera vocal rara.
const Map<String, String> kVettedFold = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ā': 'a',
  'ă': 'a',
  'ą': 'a',
  'ć': 'c',
  'ĉ': 'c',
  'ċ': 'c',
  'č': 'c',
  'ď': 'd',
  'ē': 'e',
  'ĕ': 'e',
  'ė': 'e',
  'ę': 'e',
  'ě': 'e',
  'ĝ': 'g',
  'ğ': 'g',
  'ġ': 'g',
  'ģ': 'g',
  'ĥ': 'h',
  'ĩ': 'i',
  'ī': 'i',
  'ĭ': 'i',
  'į': 'i',
  'ĵ': 'j',
  'ķ': 'k',
  'ĺ': 'l',
  'ļ': 'l',
  'ľ': 'l',
  'ń': 'n',
  'ņ': 'n',
  'ň': 'n',
  'ō': 'o',
  'ŏ': 'o',
  'ő': 'o',
  'ŕ': 'r',
  'ŗ': 'r',
  'ř': 'r',
  'ś': 's',
  'ŝ': 's',
  'ş': 's',
  'š': 's',
  'ţ': 't',
  'ť': 't',
  'ũ': 'u',
  'ū': 'u',
  'ŭ': 'u',
  'ů': 'u',
  'ű': 'u',
  'ų': 'u',
  'ŵ': 'w',
  'ŷ': 'y',
  'ź': 'z',
  'ż': 'z',
  'ž': 'z',
  'ơ': 'o',
  'ư': 'u',
  'ǎ': 'a',
  'ǐ': 'i',
  'ǒ': 'o',
  'ǔ': 'u',
  'ǖ': 'u',
  'ǘ': 'u',
  'ǚ': 'u',
  'ǜ': 'u',
  'ǟ': 'a',
  'ǡ': 'a',
  'ǧ': 'g',
  'ǩ': 'k',
  'ǫ': 'o',
  'ǭ': 'o',
  'ǰ': 'j',
  'ǵ': 'g',
  'ǹ': 'n',
  'ǻ': 'a',
  'ȁ': 'a',
  'ȃ': 'a',
  'ȅ': 'e',
  'ȇ': 'e',
  'ȉ': 'i',
  'ȋ': 'i',
  'ȍ': 'o',
  'ȏ': 'o',
  'ȑ': 'r',
  'ȓ': 'r',
  'ȕ': 'u',
  'ȗ': 'u',
  'ș': 's',
  'ț': 't',
  'ȟ': 'h',
  'ȧ': 'a',
  'ȩ': 'e',
  'ȫ': 'o',
  'ȭ': 'o',
  'ȯ': 'o',
  'ȱ': 'o',
  'ȳ': 'y'
};

/// Deshacer leet: `0` -> `o`, `@` -> `a`.
const Map<String, String> kVettedLeet = {
  '!': 'i',
  '\$': 's',
  '0': 'o',
  '1': 'i',
  '3': 'e',
  '4': 'a',
  '5': 's',
  '7': 't',
  '@': 'a'
};

/// Los simbolos de `kVettedLeet` que SOLO se traducen con letra a los dos
/// lados. Sin esa regla `puta!` normaliza a `putai` y deja de matchear.
const Set<String> kVettedLeetOnlyBetweenLetters = {'!', '\$', '@'};

/// Runs de este largo o mas colapsan a un caracter: `putooooo` -> `puto`.
/// Tres y no dos: el castellano tiene dobles (`carro`, `perro`) pero no
/// triples.
const int kVettedCollapseMin = 3;

/// Terminos de severidad `block` de UNA palabra, ya normalizados.
const Set<String> kVettedBlockWords = {
  'chupapija',
  'chupapijas',
  'cojer',
  'concha',
  'conchas',
  'conchuda',
  'conchudo',
  'culiar',
  'garcha',
  'garchame',
  'garchar',
  'hdp',
  'koncha',
  'kulo',
  'lctm',
  'marica',
  'maricon',
  'maricones',
  'matate',
  'mogolica',
  'mogolico',
  'mogolicos',
  'pedofila',
  'pedofilia',
  'pedofilo',
  'pija',
  'pijas',
  'pornhub',
  'porno',
  'pornografia',
  'puta',
  'putas',
  'putazo',
  'putito',
  'puto',
  'putos',
  'pvta',
  'pvtas',
  'pvto',
  'pvtos',
  'sidoso',
  'subnormal',
  'suicidate',
  'tortillera',
  'travuco',
  'trolo',
  'trolos',
  'verga',
  'vergas',
  'zoofilia'
};

/// Terminos de severidad `block` de VARIAS palabras, como secuencia de tokens.
const List<List<String>> kVettedBlockPhrases = [
  ['andate', 'a', 'la', 'concha'],
  ['andate', 'a', 'morir'],
  ['chupame', 'la', 'pija'],
  ['colgate', 'de', 'un', 'arbol'],
  ['gorda', 'de', 'mierda'],
  ['gordo', 'de', 'mierda'],
  ['hija', 'de', 'puta'],
  ['hijo', 'de', 'puta'],
  ['hijos', 'de', 'puta'],
  ['la', 'concha', 'de', 'su', 'madre'],
  ['la', 'concha', 'de', 'tu', 'madre'],
  ['muerta', 'de', 'hambre'],
  ['muerto', 'de', 'hambre'],
  ['negra', 'de', 'mierda'],
  ['negro', 'de', 'mierda'],
  ['ojala', 'te', 'mueras'],
  ['retrasado', 'mental'],
  ['te', 'reviento'],
  ['te', 'voy', 'a', 'cagar', 'a', 'trompadas'],
  ['te', 'voy', 'a', 'matar'],
  ['te', 'voy', 'a', 'reventar'],
  ['vaca', 'de', 'mierda']
];

/// Terminos de severidad `review` de UNA palabra.
const Set<String> kVettedReviewWords = {
  'coger',
  'cogerte',
  'culo',
  'culos',
  'estupida',
  'estupido',
  'forra',
  'forro',
  'gil',
  'gila',
  'idiota',
  'imbecil',
  'pelotuda',
  'pelotudas',
  'pelotudo',
  'pelotudos',
  'proana',
  'promia',
  'sorete',
  'tarada',
  'tarado',
  'tetas',
  'thinspiration',
  'thinspo'
};

/// Terminos de severidad `review` de VARIAS palabras.
const List<List<String>> kVettedReviewPhrases = [
  ['dejar', 'de', 'comer', 'para'],
  ['manga', 'de', 'inutiles'],
  ['pro', 'ana'],
  ['vomitar', 'despues', 'de', 'comer']
];

/// Subconjunto para la pasada antievasion: subcadena sobre el texto sin
/// separadores. Chico y de severidad alta a proposito — ver el JSON fuente.
const List<String> kVettedAntiEvasion = [
  'chupapija',
  'conchudo',
  'garchame',
  'garchar',
  'maricon',
  'mogolico',
  'pedofilia',
  'pedofilo',
  'pornhub',
  'putazo',
  'puto',
  'sidoso',
  'tortillera',
  'travuco',
  'trolo',
  'zoofilia'
];

/// Palabras legitimas que contienen un termino de `kVettedAntiEvasion`. Se
/// sacan del texto antes de la pasada B.
const Set<String> kVettedAllowlist = {
  'amputo',
  'computo',
  'computos',
  'controlo',
  'descontrolo',
  'disputo',
  'imputo',
  'reputo'
};

/// Corpus de conformidad. La suite de TypeScript corre EXACTAMENTE estos
/// mismos casos: si los dos veredictos no coinciden, una de las dos se pone
/// roja. Ninguna de las dos escribe sus expectativas a mano.
const List<({String texto, String espera, String normalizado, String por})>
    kVettedCases = [
  (
    texto: 'computadora',
    espera: 'ok',
    normalizado: 'computadora',
    por: 'contiene `puta`'
  ),
  (
    texto: 'me lo anote en la computadora',
    espera: 'ok',
    normalizado: 'me lo anote en la computadora',
    por: 'contiene `puta`'
  ),
  (
    texto: 'calculo',
    espera: 'ok',
    normalizado: 'calculo',
    por: 'contiene `culo`'
  ),
  (
    texto: 'cálculo',
    espera: 'ok',
    normalizado: 'calculo',
    por: 'contiene `culo`, con acento'
  ),
  (
    texto: 'disputa',
    espera: 'ok',
    normalizado: 'disputa',
    por: 'contiene `puta`'
  ),
  (
    texto: 'reputación',
    espera: 'ok',
    normalizado: 'reputacion',
    por: 'contiene `puta`'
  ),
  (
    texto: 'sexteto',
    espera: 'ok',
    normalizado: 'sexteto',
    por: 'contiene `sex`'
  ),
  (
    texto: 'escocia',
    espera: 'ok',
    normalizado: 'escocia',
    por: 'falso positivo clasico'
  ),
  (
    texto: 'cuatro series para el musculo dorsal',
    espera: 'ok',
    normalizado: 'cuatro series para el musculo dorsal',
    por: '`musculo` contiene `culo`: el caso de ESTE producto'
  ),
  (
    texto: 'trabajo de musculacion tres veces por semana',
    espera: 'ok',
    normalizado: 'trabajo de musculacion tres veces por semana',
    por: 'vocabulario central de la app'
  ),
  (
    texto: 'el computo de las series',
    espera: 'ok',
    normalizado: 'el computo de las series',
    por: 'contiene `puto` — el que obliga a la allowlist'
  ),
  (
    texto: 'me puse el pijama',
    espera: 'ok',
    normalizado: 'me puse el pijama',
    por: 'contiene `pija`'
  ),
  (
    texto: 'el diputado Vergara',
    espera: 'ok',
    normalizado: 'el diputado vergara',
    por: 'contiene `puta` y `verga`'
  ),
  (
    texto: 'hoy entrené piernas y me fue bien',
    espera: 'ok',
    normalizado: 'hoy entrene piernas y me fue bien',
    por: 'control: texto normal pasa'
  ),
  (texto: 'puto', espera: 'block', normalizado: 'puto', por: 'termino directo'),
  (texto: 'PUTO', espera: 'block', normalizado: 'puto', por: 'mayusculas'),
  (
    texto: 'pÚtO',
    espera: 'block',
    normalizado: 'puto',
    por: 'mayusculas mezcladas y acento'
  ),
  (
    texto: 'putooooo',
    espera: 'block',
    normalizado: 'puto',
    por: 'caracteres repetidos'
  ),
  (
    texto: 'p u t o',
    espera: 'block',
    normalizado: 'p u t o',
    por: 'separado por espacios'
  ),
  (
    texto: 'p-u-t-o',
    espera: 'block',
    normalizado: 'p-u-t-o',
    por: 'separado por guiones'
  ),
  (
    texto: 'p.u.t.o',
    espera: 'block',
    normalizado: 'p.u.t.o',
    por: 'separado por puntos'
  ),
  (texto: 'pvto', espera: 'block', normalizado: 'pvto', por: 'v por u'),
  (
    texto: 'sos un hijo de puta',
    espera: 'block',
    normalizado: 'sos un hijo de puta',
    por: 'frase de varias palabras'
  ),
  (
    texto: 'hijo  de   PUTA',
    espera: 'block',
    normalizado: 'hijo  de puta',
    por: 'frase con espacios de mas'
  ),
  (
    texto: 'te voy a matar',
    espera: 'block',
    normalizado: 'te voy a matar',
    por: 'amenaza'
  ),
  (
    texto: 'and4te a morir',
    espera: 'block',
    normalizado: 'andate a morir',
    por: 'leet: 4 -> a'
  ),
  (
    texto: 'sos un pelotudo',
    espera: 'review',
    normalizado: 'sos un pelotudo',
    por: 'insulto casual rioplatense'
  ),
  (
    texto: 'que gil',
    espera: 'review',
    normalizado: 'que gil',
    por: 'insulto leve'
  ),
  (
    texto: 'thinspo',
    espera: 'review',
    normalizado: 'thinspo',
    por: 'contenido pro trastorno alimentario'
  ),
  (
    texto: 'cuantos años entrenas por semana',
    espera: 'ok',
    normalizado: 'cuantos anos entrenas por semana',
    por:
        '`ñ` pliega a `n`: `años` -> `anos`. Vigila que nadie meta `ano` en la lista'
  ),
  (
    texto: 'hace 3 años que entreno',
    espera: 'ok',
    normalizado: 'hace e anos que entreno',
    por: 'leet `3`->`e` sobre un numero real, mas el plegado de la ñ'
  ),
  (
    texto: 'sos un puta!',
    espera: 'block',
    normalizado: 'sos un puta!',
    por:
        'el `!` final NO se traduce a `i`: si se tradujera, `putai` no matchearia'
  ),
  (
    texto: '10x3 con 90 segundos de pausa',
    espera: 'ok',
    normalizado: 'ioxe con 9o segundos de pausa',
    por:
        'notacion de series: los digitos pasan por leet y no pueden inventar un veto'
  ),
  (
    texto: 'otro loco que entrena a las 6',
    espera: 'ok',
    normalizado: 'otro loco que entrena a las 6',
    por:
        'pegado entero daria `otroloco` -> contiene `trolo`. La pasada B NO pega entre palabras'
  ),
  (
    texto: 'traeme otro lote de bandas',
    espera: 'ok',
    normalizado: 'traeme otro lote de bandas',
    por: 'mismo caso: `otrolote` contiene `trolo`'
  ),
  (
    texto: 'pvto',
    espera: 'block',
    normalizado: 'pvto',
    por: 'grafia de evasion explicita, no transformacion'
  ),
  (
    texto: 'holaputo',
    espera: 'block',
    normalizado: 'holaputo',
    por: 'pegado adentro de un token: la pasada B busca subcadena por token'
  ),
  (
    texto: 'no me controlo con la comida',
    espera: 'ok',
    normalizado: 'no me controlo con la comida',
    por: '`controlo` contiene `trolo` y esta en la allowlist'
  ),
  (
    texto: 'hice press banca con barra',
    espera: 'ok',
    normalizado: 'hice press banca con barra',
    por: 'dobles `ss` y `rr`: el colapso arranca en TRES, no en dos'
  ),
  (
    texto: 'el perro del gimnasio se llama Rocco',
    espera: 'ok',
    normalizado: 'el perro del gimnasio se llama rocco',
    por: 'tres dobles seguidas — `rr`, `ll`, `cc`'
  ),
  (
    texto: 'acción correcta en el banco',
    espera: 'ok',
    normalizado: 'accion correcta en el banco',
    por: 'doble con acento arriba: plegado y colapso se tocan'
  ),
];
