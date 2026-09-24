import * as fs from "fs";
import * as path from "path";

import {
  VETTED_BLOCK_PHRASES,
  VETTED_BLOCK_WORDS,
  VETTED_REVIEW_PHRASES,
  VETTED_REVIEW_WORDS,
} from "../moderation/vetted_terms.g";
import {
  checkText,
  normalize,
  type ModerationVerdict,
} from "../moderation/vetted_terms_filter";

/**
 * La lista ENTERA contra el filtro, y el vocabulario REAL del producto contra
 * el filtro — ESPEJO de
 * `test/core/moderation/moderation_filter_lista_completa_test.dart`.
 *
 * `vetted-terms-filter.test.ts` corre el corpus de conformidad: casos elegidos
 * a mano que prueban el ALGORITMO. Esta suite prueba lo que ese corpus no
 * puede: que CADA termino de la lista da su severidad con cada variante de
 * evasion, y que el contenido real del producto pasa entero. Ver el porque
 * completo en el espejo de Dart.
 *
 * Esta es la capa que importa: el cliente se saltea con el SDK directo, y lo
 * que corre en el servidor es este algoritmo.
 */

const RAIZ = path.resolve(__dirname, "../../..");

const block: string[] = [
  ...VETTED_BLOCK_WORDS,
  ...VETTED_BLOCK_PHRASES.map((frase) => frase.join(" ")),
];
const review: string[] = [
  ...VETTED_REVIEW_WORDS,
  ...VETTED_REVIEW_PHRASES.map((frase) => frase.join(" ")),
];
const porSeveridad: [string[], ModerationVerdict][] = [
  [block, "block"],
  [review, "review"],
];

/**
 * Las variantes de evasion que la normalizacion dice cubrir, aplicadas a UN
 * termino ya normalizado. Mismo algoritmo que `variantes()` en el espejo de
 * Dart: los separadores van ENTRE LAS LETRAS de cada palabra.
 */
function variantes(termino: string): Record<string, string> {
  const acentos: Record<string, string> = {
    a: "á", e: "é", i: "í", o: "ó", u: "ú",
  };
  const letras = [...termino];
  const entreLetras = (separador: string): string =>
    termino
      .split(" ")
      .map((palabra) => [...palabra].join(separador))
      .join(" ");

  return {
    "mayusculas": termino.toUpperCase(),
    "mayusculas alternadas": letras
      .map((c, i) => (i % 2 === 1 ? c.toUpperCase() : c))
      .join(""),
    "acentos": letras.map((c) => acentos[c] ?? c).join(""),
    "dieresis": termino.replace(/u/g, "ü"),
    "espacios entre letras": entreLetras(" "),
    "guiones entre letras": entreLetras("-"),
    "puntos entre letras": entreLetras("."),
    "leet 0 1 @ 3": termino
      .replace(/o/g, "0")
      .replace(/i/g, "1")
      .replace(/a/g, "@")
      .replace(/e/g, "3"),
    "dentro de una oracion": `mirá vos, ${termino}, te lo digo en serio`,
  };
}

/**
 * El contenido que el producto YA publica, con su origen. Mismas fuentes que
 * el espejo de Dart menos `MuscleGroup`, que vive en codigo Dart; sus
 * etiquetas las cubre esa suite.
 */
function corpusReal(): [string, string][] {
  const textos: [string, string][] = [];
  const agregar = (origen: string, valor: unknown): void => {
    if (typeof valor === "string" && valor.trim() !== "") {
      textos.push([origen, valor]);
    }
  };
  const leer = (ruta: string): unknown =>
    JSON.parse(fs.readFileSync(path.join(RAIZ, ruta), "utf8"));

  type Ejercicio = {
    id: string;
    name?: unknown;
    aliases?: unknown[];
    techniqueInstructions?: unknown[];
  };
  const catalogo =
    leer("docs/video-catalog-audit/enriched-catalog.json") as Ejercicio[];
  for (const e of catalogo) {
    agregar(`catalogo ${e.id} · name`, e.name);
    for (const alias of e.aliases ?? []) {
      agregar(`catalogo ${e.id} · alias`, alias);
    }
    for (const paso of e.techniqueInstructions ?? []) {
      agregar(`catalogo ${e.id} · tecnica`, paso);
    }
  }

  type Plantilla = {
    id: string;
    [campo: string]: unknown;
    days?: { name?: unknown; slots?: Record<string, unknown>[] }[];
  };
  const plantillas =
    leer("docs/video-catalog-audit/improved-templates.json") as Plantilla[];
  for (const p of plantillas) {
    for (const campo of ["name", "summary", "split"]) {
      agregar(`plantilla ${p.id} · ${campo}`, p[campo]);
    }
    for (const dia of p.days ?? []) {
      agregar(`plantilla ${p.id} · dia`, dia.name);
      for (const slot of dia.slots ?? []) {
        agregar(`plantilla ${p.id} · ejercicio`, slot.exerciseName);
        agregar(`plantilla ${p.id} · nota`, slot.notes);
      }
    }
  }

  for (const ruta of ["lib/l10n/intl_es_AR.arb", "lib/l10n/intl_es.arb"]) {
    const arb = leer(ruta) as Record<string, unknown>;
    for (const [clave, valor] of Object.entries(arb)) {
      if (!clave.startsWith("@")) agregar(`${ruta} · ${clave}`, valor);
    }
  }

  return textos;
}

describe("cada termino de la lista", () => {
  it("la lista no esta vacia", () => {
    // Sin esto, una lista vaciada por error deja la suite en verde sin haber
    // medido nada.
    expect(block.length).toBeGreaterThanOrEqual(60);
    expect(review.length).toBeGreaterThanOrEqual(25);
  });

  for (const [terminos, esperado] of porSeveridad) {
    for (const termino of terminos) {
      it(`${esperado.padEnd(6)} · "${termino}"`, () => {
        expect(checkText(termino)).toBe(esperado);
      });
    }
  }
});

describe("cada termino con cada variante de evasion", () => {
  for (const [terminos, esperado] of porSeveridad) {
    for (const termino of terminos) {
      it(`${esperado.padEnd(6)} · "${termino}"`, () => {
        // Todas las variantes de un termino en UN test, juntando las que se
        // escapan: el reporte dice cuales pasaron, no solo la primera.
        const escapadas: string[] = [];
        for (const [nombre, texto] of Object.entries(variantes(termino))) {
          const obtenido = checkText(texto);
          if (obtenido !== esperado) {
            escapadas.push(
              `${nombre}: "${texto}" dio ${obtenido} ` +
                `(normalizado: "${normalize(texto)}")`,
            );
          }
        }
        expect(escapadas).toEqual([]);
      });
    }
  }
});

describe("el vocabulario real del producto pasa entero", () => {
  const textos = corpusReal();

  it("el corpus se cargo", () => {
    // Si un archivo se mueve, el corpus queda vacio y el test de abajo pasa
    // sin haber mirado nada. Piso muy por debajo de lo que hay hoy, para que
    // agregar o sacar un ejercicio no lo rompa.
    expect(textos.length).toBeGreaterThan(6000);
  });

  it(`ninguno de los ${textos.length} textos da block ni review`, () => {
    const caidos = textos
      .filter(([, texto]) => checkText(texto) !== "ok")
      .map(([origen, texto]) => `${checkText(texto)} · ${origen}: "${texto}"`);
    expect(caidos).toEqual([]);
  });
});
