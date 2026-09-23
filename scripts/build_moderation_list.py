#!/usr/bin/env python3
"""Genera la lista de terminos vetados a partir de `assets/moderation/`.

FUENTE UNICA: `assets/moderation/terminos-vetados.json`. Todo lo demas se
genera.

    python3 scripts/build_moderation_list.py            # genera
    python3 scripts/build_moderation_list.py --check    # CI: falla si hay drift

Salidas:
  - lib/core/moderation/vetted_terms.g.dart
  - functions/src/moderation/vetted_terms.g.ts

## Por que se genera en vez de escribirse dos veces

El filtro corre en los dos lados: en el cliente al componer (es lo que
satisface la Guideline 1.2 de App Review, porque el contenido no llega a
postearse) y en una Cloud Function al escribir (porque el cliente se puede
saltear con el SDK directo). Dos listas escritas a mano en dos lenguajes se
separan, y cuando se separan nadie se entera: los tests de cada lado siguen
verdes porque cada uno testea SU copia.

Este repo ya lo vivio tres veces. `Block.toJson()` emitia `id` y el `hasOnly`
de las rules no lo incluia. `feedbackCounts` (#1160). Y `Post.reactionCounts`,
que rompio la publicacion de posts durante SIETE SEMANAS con la suite entera en
verde, porque el fixture `validPost()` de `post-create-shape-rules.test.ts`
omitia el campo que el modelo si emitia.

## Que se normaliza aca y que en runtime

Aca se normalizan los TERMINOS (minuscula, sin diacriticos, tokenizados). Se
hace una sola vez y los dos lenguajes reciben la forma ya resuelta, asi que la
normalizacion de la lista no puede divergir entre Dart y TypeScript: no existe
dos veces.

En runtime cada lenguaje normaliza el TEXTO DEL USUARIO. Esa parte si esta
escrita dos veces, y es lo que el corpus de `cases` existe para vigilar.
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "moderation" / "terminos-vetados.json"
DART_OUT = ROOT / "lib/core/moderation/vetted_terms.g.dart"
TS_OUT = ROOT / "functions/src/moderation/vetted_terms.g.ts"

BANNER = "GENERADO POR scripts/build_moderation_list.py — NO EDITAR A MANO."
ESPERAS = {"ok", "block", "review"}

# Deshacer leet. `0->o` y companía.
#
# Se emite a los dos lenguajes en vez de escribirse dos veces por el mismo
# motivo que la lista: es la MISMA tabla, y dos copias a mano se separan.
LEET = {
    "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t",
    "@": "a", "$": "s", "!": "i",
}

# `!` solo se traduce cuando tiene letra a los DOS lados. Sin esa regla `puta!`
# normaliza a `putai`, que no matchea `puta` por palabra completa: el leet,
# puesto a lo bruto, produce falsos NEGATIVOS justo sobre el texto mas comun
# (un insulto con signo de exclamacion al final).
#
# `@` y `$` NO estan aca, y antes si estaban. Con la misma regla que `!`, la
# forma mas natural de escribir en leet un termino femenino —`put@`, `p1j@`,
# `c0nch@`— pasaba entera: la `@` del final no tiene letra a la derecha, no se
# traducia, y quedaba `put`. Lo mismo `@ndate` al principio, y la `@` suelta de
# `te voy @ matar`, que es la preposicion. El motivo de la regla es propio de
# `!` —es puntuacion, y cierra frases—; `@` y `$` no cierran nada en
# castellano. Se traducen siempre, igual que los digitos.
LEET_SOLO_ENTRE_LETRAS = {"!"}

# Runs de 3 o mas caracteres iguales colapsan a uno: `putooooo` -> `puto`.
#
# Tres y no dos: el castellano no tiene triples, pero si dobles (`carro`,
# `perro`, `llave`, `accion`). Colapsar dobles las romperia todas.
COLAPSO_MINIMO = 3

# Largo maximo de un fragmento para que la pasada antievasion lo PEGUE con el
# de al lado.
#
# La version anterior pegaba solo corridas de UN caracter, y `pu-to` o `p-uto`
# se le escapaban: dos fragmentos de dos y tres letras, ninguno de largo 1, asi
# que no se juntaban y ninguno contenia el termino. Un separador alcanzaba para
# saltear la capa entera.
#
# Pegar TODO tampoco sirve: `otro loco` da `otroloco`, que contiene `trolo`, y
# es castellano rioplatense corriente.
#
# El 3 sale de la diferencia real entre los dos casos. Quien parte una palabra
# para evadir produce fragmentos CORTOS (`p u t o`, `pu-to`, `con-chudo`); el
# castellano separa palabras LARGAS (`otro` y `loco`, `otro` y `lote`, cuatro
# letras cada una). Tres es el ultimo largo donde lo primero es mucho mas
# probable que lo segundo.
JOIN_MAX_FRAGMENT = 3


def _rangos_combinantes() -> list[tuple[int, int]]:
    """Los bloques Unicode de marcas combinantes. Limites FIJOS, no derivados.

    Hacen falta porque el mapa de plegado solo cubre caracteres PRECOMPUESTOS.
    El mismo texto puede llegar descompuesto —`u` seguido de U+0301 en vez de
    `ú`— y entonces la marca sobrevive, parte el token en dos y el termino no
    matchea: `puto` escrito `pu´to` pasaba, mientras que el `púto` precompuesto
    se bloqueaba. Los dos se ven IDENTICOS en pantalla.

    ## Por que NO se barre por categoria

    La primera version escaneaba el BMP entero preguntando
    `unicodedata.category(c) == 'Mn'`, y eso hace que la salida del generador
    dependa de la VERSION DE UNICODE del interprete que lo corre. Esta maquina
    tiene Python 3.14 con Unicode 16.0.0 y el runner de CI trae otra: el mismo
    comando producia dos archivos distintos, y el gate `Generados al dia` se
    puso rojo — que es exactamente para lo que existe.

    Un generador cuya salida depende de la maquina no es un generador: es la
    misma divergencia que todo esto viene a evitar, corrida un escalon.

    Los LIMITES DE BLOQUE, en cambio, son inmutables en el estandar: Unicode no
    mueve un bloque ya asignado. Estos cinco contienen las marcas que se
    combinan con letras latinas, que es lo unico que este filtro necesita. De
    los 212 rangos que devolvia el barrido por categoria, 204 caian fuera de
    estos cinco —hebreo, arabe, devanagari—: irrelevantes para un filtro en
    castellano rioplatense, y la fuente entera de la deriva.
    """
    return [
        (0x0300, 0x036F),  # Combining Diacritical Marks — el que importa
        (0x1AB0, 0x1AFF),  # Combining Diacritical Marks Extended
        (0x1DC0, 0x1DFF),  # Combining Diacritical Marks Supplement
        (0x20D0, 0x20FF),  # Combining Diacritical Marks for Symbols
        (0xFE20, 0xFE2F),  # Combining Half Marks
    ]


def _mapa_de_plegado() -> dict[str, str]:
    """`á`->`a`, `ñ`->`n`, para todo el latino extendido.

    Sale de `unicodedata`, no de una tabla escrita a mano, y se emite a Dart y
    a TypeScript. Ninguno de los dos tiene un NFD en su biblioteca estandar, y
    dos tablas escritas a mano divergen en la tercera vocal rara.

    OJO: `ñ` -> `n`, asi que `año` normaliza a `ano`. Es lo que hace Python y
    por lo tanto lo que hacen los terminos generados, asi que los tres lados
    coinciden. Pero significa que meter `ano` en la lista de vetados
    bloquearia `año`, `años`, `añadir` y `pequeño`. Hay un caso en el corpus
    que lo vigila.
    """
    # Latin-1 Supplement (00C0-00FF) y Latin Extended-A (0100-017F): los dos
    # asignados por completo desde Unicode 1.1 y congelados desde entonces.
    #
    # NO se llega hasta 0x0250 (Latin Extended-B) por el mismo motivo que los
    # rangos combinantes: ese bloque recibio asignaciones nuevas entre
    # versiones, asi que incluirlo hace que la tabla dependa del interprete que
    # corre el generador. Lo que queda afuera —`ǎ`, `ǧ` y companía— no es
    # castellano ni aparece en el vocabulario de este producto.
    out: dict[str, str] = {}
    for cp in range(0x00C0, 0x0180):
        ch = chr(cp)
        bajo = ch.lower()
        # Solo claves de UN codepoint. La `İ` turca (U+0130) baja a dos —`i` mas
        # una combinante— y los dos matchers recorren el texto caracter por
        # caracter, asi que una clave de dos nunca se encontraria. Entraria al
        # mapa y no haria nada: una entrada que aparenta cubrir algo.
        if len(bajo) != 1:
            continue
        plano = sin_diacriticos(bajo)
        if plano != bajo and plano.isascii() and plano.isalpha():
            out[bajo] = plano

    # El tamano queda PINEADO.
    #
    # Lo que se emite tiene que ser identico en cualquier maquina, o el gate
    # `Generados al dia` se pone rojo sin decir por que — que es justo lo que
    # paso: la version anterior barria por categoria Unicode y esta maquina
    # (Unicode 16.0.0) producia un archivo distinto al del runner.
    #
    # El rango que se recorre esta congelado desde Unicode 1.1, asi que este
    # numero no deberia moverse nunca. Si se mueve, algo cambio en el
    # interprete y hay que MIRARLO, no subir el numero de taquito: la salida
    # del generador acaba de volverse dependiente de la maquina otra vez.
    if len(out) != 80:
        sys.exit(f"[!] el mapa de plegado tiene {len(out)} entradas y se "
                 "esperaban 80. El rango 00C0-017F esta congelado desde "
                 "Unicode 1.1, asi que esto significa que la salida del "
                 "generador dejo de ser identica entre maquinas. Mirá qué "
                 "cambió antes de tocar este número.")
    return out


def sin_diacriticos(s: str) -> str:
    """NFD y descarta las marcas combinantes. `mogólico` -> `mogolico`."""
    return "".join(c for c in unicodedata.normalize("NFD", s)
                   if unicodedata.category(c) != "Mn")


def tokens(s: str) -> list[str]:
    """Minuscula, sin diacriticos, partido en palabras.

    Parte por todo lo que no sea letra o digito, asi que `hijo de puta` da
    tres tokens y `p.u.t.o` da cuatro.
    """
    return [t for t in re.split(r"[^0-9a-z]+", sin_diacriticos(s.lower())) if t]


def solo_letras(s: str) -> str:
    """Todo pegado, sin separadores. Para la pasada antievasion."""
    return re.sub(r"[^0-9a-z]", "", sin_diacriticos(s.lower()))


def normalizar(texto: str) -> str:
    """La normalizacion DE REFERENCIA. Dart y TypeScript son puertos de esto.

    El corpus guarda la salida de esta funcion para cada caso, y las dos suites
    la comparan ademas del veredicto. Sin eso el corpus solo caza una
    divergencia cuando llega a voltear un `ok` en `block`: dos normalizaciones
    distintas que no cruzan ese umbral quedan vivas, con las dos suites en
    verde, hasta el dia que alguien agrega un termino y el bug aparece lejos
    de donde se escribio.

    Que la referencia viva aca y no en uno de los dos runtimes es a proposito.
    Si la referencia fuera Dart, TypeScript se conformaria a Dart y nadie
    estaria mirando a Dart; con el generador en el medio, los dos se conforman
    a lo mismo y ninguno es juez de su propio caso.
    """
    s = sin_diacriticos(texto.lower())

    # Leet. `!` solo con letra a los DOS lados: ver LEET_SOLO_ENTRE_LETRAS.
    chars = list(s)
    fuera = []
    for i, ch in enumerate(chars):
        rep = LEET.get(ch)
        if rep is None:
            fuera.append(ch)
            continue
        if ch in LEET_SOLO_ENTRE_LETRAS:
            antes = i > 0 and _es_alnum(chars[i - 1])
            despues = i + 1 < len(chars) and _es_alnum(chars[i + 1])
            fuera.append(rep if antes and despues else ch)
        else:
            fuera.append(rep)
    s = "".join(fuera)

    # Colapsar runs de COLAPSO_MINIMO o mas.
    out = []
    i = 0
    while i < len(s):
        j = i
        while j < len(s) and s[j] == s[i]:
            j += 1
        largo = j - i
        out.append(s[i] if largo >= COLAPSO_MINIMO else s[i] * largo)
        i = j
    return "".join(out)


def _es_alnum(ch: str) -> bool:
    return len(ch) == 1 and ("0" <= ch <= "9" or "a" <= ch <= "z")


def cargar() -> dict:
    if not SRC.exists():
        sys.exit(f"[!] falta {SRC.relative_to(ROOT)}")
    data = json.loads(SRC.read_text(encoding="utf-8"))

    for clave in ("version", "severities", "antievasion", "allowlist", "cases"):
        if clave not in data:
            sys.exit(f"[!] {SRC.name}: falta la clave '{clave}'")

    sev = data["severities"]
    block = [tokens(t) for t in sev.get("block", [])]
    review = [tokens(t) for t in sev.get("review", [])]
    allow = {solo_letras(t) for t in data["allowlist"]}
    anti = [solo_letras(t) for t in data["antievasion"]]

    # Un termino con un caracter de leet queda MUERTO, y muerto en silencio.
    #
    # Los terminos se normalizan aca (minuscula, sin diacriticos, tokenizados)
    # pero el texto del usuario ademas pasa por leet en runtime. Un termino
    # `put0` se guardaria tal cual, mientras que el texto `put0` llegaria al
    # comparador ya convertido en `puto`. Nunca se encontrarian: la entrada
    # estaria en la lista, se veria en el diff, y no cazaria nada jamas.
    #
    # Es exactamente el modo de falla que AGENTS.md 11.1 describe — algo que
    # parece cobertura y no lo es — y del lado peor, porque el sintoma es que
    # el filtro deja pasar contenido que alguien creyo haber vetado.
    con_leet = sorted({t for t in sev.get("block", []) + sev.get("review", [])
                       if any(c in LEET for c in sin_diacriticos(t.lower()))})
    if con_leet:
        ejemplos = ", ".join(f"{k}->{v}" for k, v in sorted(LEET.items()))
        sys.exit(f"[!] {SRC.name}: estos terminos tienen caracteres de leet y "
                 f"quedarian muertos: {con_leet}\n"
                 f"    El texto del usuario se deshace el leet ANTES de "
                 f"comparar ({ejemplos}), asi que escribí el termino ya "
                 f"resuelto. `put0` se caza solo con `puto`.")

    if any(not t for t in block + review):
        sys.exit(f"[!] {SRC.name}: hay un termino vacio o sin letras.")
    if any(not t for t in anti):
        sys.exit(f"[!] {SRC.name}: hay una entrada vacia en 'antievasion'.")

    # --- validaciones que impiden una lista que se contradice a si misma ---
    #
    # Ninguna de estas es teorica: las tres describen un estado en el que el
    # filtro se comporta distinto segun el orden en que mire las listas, y el
    # orden es justo lo que Dart y TypeScript pueden implementar distinto.

    b = {" ".join(t) for t in block}
    r = {" ".join(t) for t in review}
    if b & r:
        sys.exit(f"[!] {SRC.name}: estos terminos estan en 'block' Y en "
                 f"'review', asi que su severidad depende del orden de "
                 f"evaluacion: {sorted(b & r)}")

    en_ambas = {t for t in b | r if solo_letras(t) in allow}
    if en_ambas:
        sys.exit(f"[!] {SRC.name}: estos terminos estan vetados Y en la "
                 f"allowlist, o sea prohibidos y permitidos a la vez: "
                 f"{sorted(en_ambas)}")

    # La pasada B siempre resuelve `block`. Si un termino de `antievasion`
    # estuviera en `review`, cazarlo por subcadena le subiria la severidad en
    # silencio: el mismo texto daria `review` escrito normal y `block` escrito
    # con separadores. Exigir `block` hace que esa contradiccion no se pueda
    # escribir.
    solo_block = {solo_letras(t) for t in b}
    solo_review = {solo_letras(t) for t in r}
    fuera = [a for a in anti if a not in solo_block]
    if fuera:
        detalle = [f"{a} (esta en 'review')" if a in solo_review
                   else f"{a} (no esta vetado)" for a in fuera]
        sys.exit(f"[!] {SRC.name}: la pasada B siempre resuelve 'block', asi "
                 f"que todo termino de 'antievasion' tiene que estar en "
                 f"'block'. Estos no: {detalle}")

    # Una entrada de allowlist que no contenga NINGUN termino de antievasion
    # no tapa nada: la pasada A compara por palabra completa, asi que ahi la
    # allowlist es un no-op, y la pasada B solo mira `antievasion`. Sin este
    # check la lista se llena de palabras que parecen defender algo — el mismo
    # problema que AGENTS.md 11.1 describe para las advertencias falsas.
    inutiles = [w for w in sorted(allow) if not any(a in w for a in anti)]
    if inutiles:
        sys.exit(f"[!] {SRC.name}: estas entradas de 'allowlist' no contienen "
                 f"ningun termino de 'antievasion', asi que no tapan nada. "
                 f"Sacalas, o agregá a 'antievasion' el termino que creias "
                 f"que estaban tapando: {inutiles}")

    # Un termino de antievasion que sea subcadena de una palabra de la
    # allowlist es lo que la allowlist existe para tapar. Que sea subcadena de
    # OTRO termino de antievasion, en cambio, es redundancia: el mas corto ya
    # lo caza, y el largo solo sirve para que alguien crea que hace falta.
    for a in anti:
        for otro in anti:
            if a != otro and a in otro:
                sys.exit(f"[!] {SRC.name}: 'antievasion' tiene {otro!r}, que "
                         f"ya esta cubierto por {a!r}. Sacá el largo.")

    casos = []
    for i, c in enumerate(data["cases"]):
        if "texto" not in c or "espera" not in c:
            sys.exit(f"[!] {SRC.name}: el caso #{i} no tiene 'texto'/'espera'")
        if c["espera"] not in ESPERAS:
            sys.exit(f"[!] {SRC.name}: el caso #{i} espera {c['espera']!r}, "
                     f"que no es uno de {sorted(ESPERAS)}")
        casos.append((c["texto"], c["espera"], c.get("por", ""),
                      normalizar(c["texto"])))

    if not casos:
        sys.exit(f"[!] {SRC.name}: 'cases' esta vacio. El corpus es lo unico "
                 "que compara Dart contra TypeScript; sin el, las dos "
                 "implementaciones pueden divergir en silencio.")

    return {
        "version": data["version"],
        "block_palabras": sorted({t[0] for t in block if len(t) == 1}),
        "block_frases": sorted([t for t in block if len(t) > 1]),
        "review_palabras": sorted({t[0] for t in review if len(t) == 1}),
        "review_frases": sorted([t for t in review if len(t) > 1]),
        "antievasion": sorted(set(anti)),
        "allowlist": sorted(allow),
        "casos": casos,
        "plegado": _mapa_de_plegado(),
        "leet": LEET,
        "leet_entre_letras": sorted(LEET_SOLO_ENTRE_LETRAS),
        "colapso_minimo": COLAPSO_MINIMO,
        "join_max": JOIN_MAX_FRAGMENT,
        "combinantes": _rangos_combinantes(),
    }


def dart_str(s: str) -> str:
    return "'" + s.replace("\\", "\\\\").replace("'", r"\'").replace("$", r"\$") + "'"


def ts_str(s: str) -> str:
    return json.dumps(s, ensure_ascii=False)


def emitir_dart(d: dict) -> str:
    def lista(xs):
        return "[" + ", ".join(dart_str(x) for x in xs) + "]"

    def frases(xs):
        return "[" + ", ".join(lista(x) for x in xs) + "]"

    casos = ",\n".join(
        f"  (texto: {dart_str(t)}, espera: {dart_str(e)}, "
        f"normalizado: {dart_str(n)}, por: {dart_str(p)})"
        for t, e, p, n in d["casos"])

    fold = ", ".join(f"{dart_str(k)}: {dart_str(v)}"
                     for k, v in sorted(d["plegado"].items()))
    leet = ", ".join(f"{dart_str(k)}: {dart_str(v)}"
                     for k, v in sorted(d["leet"].items()))
    leet_entre = ", ".join(dart_str(k) for k in d["leet_entre_letras"])
    colapso = d["colapso_minimo"]
    join_max = d["join_max"]
    comb = ", ".join(f"0x{a:04X}, 0x{b:04X}" for a, b in d["combinantes"])

    return f'''// {BANNER}
//
// Fuente: assets/moderation/terminos-vetados.json
// El espejo de este archivo es functions/src/moderation/vetted_terms.g.ts, y
// sale del MISMO origen en la misma corrida.
library;

/// Version del corpus. Sube cuando cambia la lista.
const int kVettedTermsVersion = {d["version"]};

/// `á` -> `a`, `ñ` -> `n`. Sale de `unicodedata` de Python, no de una tabla
/// escrita a mano: ni Dart ni TypeScript traen NFD en su biblioteca estandar,
/// y dos tablas a mano divergen en la tercera vocal rara.
const Map<String, String> kVettedFold = {{{fold}}};

/// Deshacer leet: `0` -> `o`, `@` -> `a`.
const Map<String, String> kVettedLeet = {{{leet}}};

/// Los simbolos de `kVettedLeet` que SOLO se traducen con letra a los dos
/// lados. Sin esa regla `puta!` normaliza a `putai` y deja de matchear.
const Set<String> kVettedLeetOnlyBetweenLetters = {{{leet_entre}}};

/// Runs de este largo o mas colapsan a un caracter: `putooooo` -> `puto`.
/// Tres y no dos: el castellano tiene dobles (`carro`, `perro`) pero no
/// triples.
const int kVettedCollapseMin = {colapso};

/// Largo maximo de un fragmento para que la pasada antievasion lo PEGUE con el
/// de al lado. Ver el porque en scripts/build_moderation_list.py.
const int kVettedJoinMaxFragment = {join_max};

/// Rangos `[desde, hasta]` de marcas combinantes (categoria Unicode `Mn`),
/// aplanados. Se descartan antes de tokenizar: sin esto, el mismo texto llega
/// descompuesto —`u` + U+0301 en vez de `ú`— la marca parte el token en dos y
/// el termino no matchea, mientras que la forma precompuesta si se bloquea.
/// Los dos se ven IDENTICOS en pantalla.
const List<int> kVettedCombiningRanges = [{comb}];

/// Terminos de severidad `block` de UNA palabra, ya normalizados.
const Set<String> kVettedBlockWords = {{{", ".join(dart_str(x) for x in d["block_palabras"])}}};

/// Terminos de severidad `block` de VARIAS palabras, como secuencia de tokens.
const List<List<String>> kVettedBlockPhrases = {frases(d["block_frases"])};

/// Terminos de severidad `review` de UNA palabra.
const Set<String> kVettedReviewWords = {{{", ".join(dart_str(x) for x in d["review_palabras"])}}};

/// Terminos de severidad `review` de VARIAS palabras.
const List<List<String>> kVettedReviewPhrases = {frases(d["review_frases"])};

/// Subconjunto para la pasada antievasion: subcadena sobre el texto sin
/// separadores. Chico y de severidad alta a proposito — ver el JSON fuente.
const List<String> kVettedAntiEvasion = {lista(d["antievasion"])};

/// Palabras legitimas que contienen un termino de `kVettedAntiEvasion`. Se
/// sacan del texto antes de la pasada B.
const Set<String> kVettedAllowlist = {{{", ".join(dart_str(x) for x in d["allowlist"])}}};

/// Corpus de conformidad. La suite de TypeScript corre EXACTAMENTE estos
/// mismos casos: si los dos veredictos no coinciden, una de las dos se pone
/// roja. Ninguna de las dos escribe sus expectativas a mano.
const List<({{String texto, String espera, String normalizado, String por}})>\n    kVettedCases = [
{casos},
];
'''


def emitir_ts(d: dict) -> str:
    def lista(xs):
        return "[" + ", ".join(ts_str(x) for x in xs) + "]"

    def frases(xs):
        return "[" + ", ".join(lista(x) for x in xs) + "]"

    casos = ",\n".join(
        f"  {{ texto: {ts_str(t)}, espera: {ts_str(e)}, "
        f"normalizado: {ts_str(n)}, por: {ts_str(p)} }}"
        for t, e, p, n in d["casos"])

    fold_ts = ", ".join(f"{ts_str(k)}: {ts_str(v)}"
                        for k, v in sorted(d["plegado"].items()))
    leet_ts = ", ".join(f"{ts_str(k)}: {ts_str(v)}"
                        for k, v in sorted(d["leet"].items()))
    leet_entre_ts = "[" + ", ".join(ts_str(k)
                                    for k in d["leet_entre_letras"]) + "]"
    colapso_ts = d["colapso_minimo"]
    join_max_ts = d["join_max"]
    comb_ts = ", ".join(f"0x{a:04X}, 0x{b:04X}" for a, b in d["combinantes"])

    return f'''// {BANNER}
//
// Fuente: assets/moderation/terminos-vetados.json
// El espejo de este archivo es lib/core/moderation/vetted_terms.g.dart, y sale
// del MISMO origen en la misma corrida.

/** Version del corpus. Sube cuando cambia la lista. */
export const VETTED_TERMS_VERSION = {d["version"]};

/**
 * `á` -> `a`, `ñ` -> `n`. Sale de `unicodedata` de Python, no de una tabla
 * escrita a mano: ni Dart ni TypeScript traen NFD en su biblioteca estandar,
 * y dos tablas a mano divergen en la tercera vocal rara.
 */
export const VETTED_FOLD: Readonly<Record<string, string>> = {{{fold_ts}}};

/** Deshacer leet: `0` -> `o`, `@` -> `a`. */
export const VETTED_LEET: Readonly<Record<string, string>> = {{{leet_ts}}};

/**
 * Los simbolos de `VETTED_LEET` que SOLO se traducen con letra a los dos
 * lados. Sin esa regla `puta!` normaliza a `putai` y deja de matchear.
 */
export const VETTED_LEET_ONLY_BETWEEN_LETTERS: ReadonlySet<string> = new Set({leet_entre_ts});

/**
 * Runs de este largo o mas colapsan a un caracter: `putooooo` -> `puto`.
 * Tres y no dos: el castellano tiene dobles (`carro`, `perro`) pero no
 * triples.
 */
export const VETTED_COLLAPSE_MIN = {colapso_ts};

/**
 * Largo maximo de un fragmento para que la pasada antievasion lo PEGUE con el
 * de al lado. Ver el porque en scripts/build_moderation_list.py.
 */
export const VETTED_JOIN_MAX_FRAGMENT = {join_max_ts};

/**
 * Rangos `[desde, hasta]` de marcas combinantes (categoria Unicode `Mn`),
 * aplanados. Se descartan antes de tokenizar: sin esto el mismo texto llega
 * descompuesto —`u` + U+0301 en vez de `ú`—, la marca parte el token en dos y
 * el termino no matchea, mientras que la forma precompuesta si se bloquea.
 */
export const VETTED_COMBINING_RANGES: readonly number[] = [{comb_ts}];

/** Terminos de severidad `block` de UNA palabra, ya normalizados. */
export const VETTED_BLOCK_WORDS: ReadonlySet<string> = new Set({lista(d["block_palabras"])});

/** Terminos de severidad `block` de VARIAS palabras, como secuencia de tokens. */
export const VETTED_BLOCK_PHRASES: readonly (readonly string[])[] = {frases(d["block_frases"])};

/** Terminos de severidad `review` de UNA palabra. */
export const VETTED_REVIEW_WORDS: ReadonlySet<string> = new Set({lista(d["review_palabras"])});

/** Terminos de severidad `review` de VARIAS palabras. */
export const VETTED_REVIEW_PHRASES: readonly (readonly string[])[] = {frases(d["review_frases"])};

/**
 * Subconjunto para la pasada antievasion: subcadena sobre el texto sin
 * separadores. Chico y de severidad alta a proposito — ver el JSON fuente.
 */
export const VETTED_ANTI_EVASION: readonly string[] = {lista(d["antievasion"])};

/**
 * Palabras legitimas que contienen un termino de `VETTED_ANTI_EVASION`. Se
 * sacan del texto antes de la pasada B.
 */
export const VETTED_ALLOWLIST: ReadonlySet<string> = new Set({lista(d["allowlist"])});

/**
 * Corpus de conformidad. La suite de Dart corre EXACTAMENTE estos mismos
 * casos: si los dos veredictos no coinciden, una de las dos se pone roja.
 * Ninguna de las dos escribe sus expectativas a mano.
 */
export const VETTED_CASES: readonly {{\n  texto: string;\n  espera: string;\n  normalizado: string;\n  por: string;\n}}[] = [
{casos},
];
'''


def dart_format(path: Path) -> None:
    """Igual que build_legal_content.py: el gate de AGENTS.md corre
    `dart format .`, asi que emitir sin formatear dejaria `--check` en rojo
    para siempre."""
    if not shutil.which("dart"):
        print("[!] `dart` no esta en PATH: salida Dart sin formatear.",
              file=sys.stderr)
        return
    subprocess.run(["dart", "format", str(path)], check=False,
                   capture_output=True)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true",
                    help="no escribe; falla si lo generado esta desactualizado")
    args = ap.parse_args()

    d = cargar()
    dart = emitir_dart(d)
    ts = emitir_ts(d)

    if args.check:
        # Se compara contra el MISMO formato que se escribe: si no, el gate
        # reportaria desfasaje eterno por un espacio.
        tmp = ROOT / "build" / ".moderation-check.dart"
        tmp.parent.mkdir(parents=True, exist_ok=True)
        tmp.write_text(dart, encoding="utf-8")
        dart_format(tmp)
        dart = tmp.read_text(encoding="utf-8")
        tmp.unlink(missing_ok=True)

        stale = []
        for path, esperado in ((DART_OUT, dart), (TS_OUT, ts)):
            if not path.exists() or path.read_text(encoding="utf-8") != esperado:
                stale.append(str(path.relative_to(ROOT)))
        if stale:
            print("[!] Desfasaje: se edito la lista de terminos vetados y no "
                  "se regenero.\n"
                  "    Corre: python3 scripts/build_moderation_list.py\n",
                  file=sys.stderr)
            for s in stale:
                print(f"      · {s}", file=sys.stderr)
            return 1
        print("[OK] Lista de terminos vetados al dia.")
        return 0

    for path, contenido in ((DART_OUT, dart), (TS_OUT, ts)):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contenido, encoding="utf-8")
    dart_format(DART_OUT)

    print(f"[OK] {DART_OUT.relative_to(ROOT)}")
    print(f"[OK] {TS_OUT.relative_to(ROOT)}")
    print(f"     block: {len(d['block_palabras'])} palabras + "
          f"{len(d['block_frases'])} frases")
    print(f"     review: {len(d['review_palabras'])} palabras + "
          f"{len(d['review_frases'])} frases")
    print(f"     antievasion: {len(d['antievasion'])}  "
          f"allowlist: {len(d['allowlist'])}  casos: {len(d['casos'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
