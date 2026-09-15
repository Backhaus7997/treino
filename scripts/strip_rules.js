#!/usr/bin/env node
/**
 * strip_rules.js — genera `firestore.deploy.rules` sacándole los comentarios a
 * `firestore.rules`, y falla si algún ruleset se pasa del límite de Firebase.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  POR QUÉ EXISTE ESTO
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Un ruleset de Firebase no puede superar **262.144 bytes (256 KiB)**, y el
 * `firestore.rules` de este repo los cruzó el **2026-09-10**, en `58324d29`,
 * **por cinco bytes**.
 *
 * Nadie se enteró durante cinco días, y el motivo es el peor posible: la API
 * contesta `400 Request contains an invalid argument` **sin decir el tamaño**.
 * Se lee como un error de sintaxis. Así que el deploy fallaba, parecía un
 * problema del cambio que uno estaba haciendo, y el archivo seguía creciendo.
 *
 * El costo real: **nueve commits de reglas que nunca llegaron a producción**,
 * dos de ellos las reglas de moderación y bloqueo de usuarios. Estaban
 * mergeadas, testeadas, y no se aplicaban del lado del servidor.
 *
 * ── Por qué se sacan los comentarios y no se recortan ──
 *
 * El **70,6%** de `firestore.rules` son comentarios. Sin ellos el archivo pesa
 * 84 KB: el 32% del límite. O sea que las REGLAS no son el problema — la prosa
 * lo es, y esa prosa es lo mejor que tiene este repo. Explica por qué cada
 * predicado es como es, y más de una vez fue lo único que evitó que alguien
 * "simplificara" un gate de seguridad.
 *
 * Recortarla para entrar en un límite de bytes sería pagar con lo que más vale
 * para satisfacer una restricción que no tiene nada que ver con el contenido.
 * Los comentarios no existen en runtime: el ruleset desplegado es SEMÁNTICAMENTE
 * IDÉNTICO al fuente.
 *
 * ── El contrato ──
 *
 * - `firestore.rules` es la FUENTE DE VERDAD. Es lo que se edita, lo que leen
 *   los 907 tests de reglas, y lo que se revisa en un PR.
 * - `firestore.deploy.rules` es un ARTEFACTO GENERADO. Está en `.gitignore`,
 *   no se edita a mano, y se regenera en cada deploy por el `predeploy` de
 *   `firebase.json`.
 * - `storage.rules` NO se procesa: está al 10% del límite y se deploya tal
 *   cual, con comentarios y todo. Acá sólo se le verifica el tamaño, para que
 *   el día que se acerque se entere alguien.
 *
 * ── Qué garantiza este script, y qué no ──
 *
 * Garantiza el TAMAÑO: si el resultado no entra, sale con código 1 y el deploy
 * no arranca. Ese es el bug que costó cinco días.
 *
 * NO garantiza que el stripper sea correcto en abstracto — eso se verificó
 * corriendo las 907 pruebas de reglas contra el archivo generado. Si algún día
 * se toca `stripComments()`, hay que repetir esa verificación.
 *
 * Uso:
 *   node scripts/strip_rules.js          # genera y valida (lo corre predeploy)
 *   node scripts/strip_rules.js --check  # sólo valida, no escribe (lo corre CI)
 */

"use strict";

const fs = require("fs");
const path = require("path");

/** El tope de un ruleset, en bytes. 256 KiB. */
const LIMIT = 262144;

/** Debajo de esto no avisa; arriba, advierte sin fallar. */
const WARN_RATIO = 0.8;

const ROOT = path.resolve(__dirname, "..");
const SOURCE = path.join(ROOT, "firestore.rules");
const OUTPUT = path.join(ROOT, "firestore.deploy.rules");
const STORAGE = path.join(ROOT, "storage.rules");

const BACKSLASH = 92;

/**
 * Saca los comentarios `//` que NO estén dentro de un string literal, y las
 * líneas que quedan vacías.
 *
 * El recorrido es carácter por carácter y no un regex a propósito: un
 * `/\/\/.*$/` se comería el `//` de una URL adentro de un string, y en estas
 * reglas hay strings con paths y patrones. Se lleva el estado de comilla
 * abierta (simple o doble) y sólo corta cuando está afuera.
 *
 * El `charCodeAt(i - 1) !== BACKSLASH` es para no cerrar la comilla en un
 * escape (`'no \' cierra'`). En `i === 0` devuelve NaN, que tampoco es 92, así
 * que el borde está cubierto sin un caso especial.
 */
function stripComments(src) {
  const out = [];
  for (const line of src.split("\n")) {
    let quote = null;
    let cut = -1;
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      if (quote) {
        if (c === quote && line.charCodeAt(i - 1) !== BACKSLASH) quote = null;
        continue;
      }
      if (c === "'" || c === '"') {
        quote = c;
        continue;
      }
      if (c === "/" && line[i + 1] === "/") {
        cut = i;
        break;
      }
    }
    const kept = (cut >= 0 ? line.slice(0, cut) : line).replace(/\s+$/, "");
    if (kept.trim() !== "") out.push(kept);
  }
  return out.join("\n") + "\n";
}

const bytes = (s) => Buffer.byteLength(s, "utf8");
const pct = (n) => `${Math.round((100 * n) / LIMIT)}%`;

function main() {
  const checkOnly = process.argv.includes("--check");

  if (!fs.existsSync(SOURCE)) {
    console.error(`strip_rules: no encuentro ${SOURCE}`);
    process.exit(1);
  }

  const source = fs.readFileSync(SOURCE, "utf8");
  const stripped = stripComments(source);
  const before = bytes(source);
  const after = bytes(stripped);

  console.log(
    `firestore.rules        ${before} bytes (${pct(before)} del límite)`,
  );
  console.log(
    `firestore.deploy.rules ${after} bytes (${pct(after)}) — ` +
      `${(100 * (before - after) / before).toFixed(1)}% eran comentarios`,
  );

  let failed = false;

  if (after > LIMIT) {
    console.error(
      `\n✗ firestore.deploy.rules se pasa del límite por ${after - LIMIT} bytes.\n` +
        `  Sacarle los comentarios YA NO ALCANZA: hay que partir las reglas o\n` +
        `  reducirlas de verdad. Ver el encabezado de este script.`,
    );
    failed = true;
  } else if (after > LIMIT * WARN_RATIO) {
    console.warn(
      `\n⚠ firestore.deploy.rules está al ${pct(after)} del límite. ` +
        `Quedan ${LIMIT - after} bytes.`,
    );
  }

  // `storage.rules` se deploya tal cual, con comentarios. Se lo mide igual para
  // que nadie se entere por un 400 sin explicación, que es como nos enteramos
  // de éste.
  if (fs.existsSync(STORAGE)) {
    const st = bytes(fs.readFileSync(STORAGE, "utf8"));
    console.log(`storage.rules          ${st} bytes (${pct(st)}) — sin procesar`);
    if (st > LIMIT) {
      console.error(
        `\n✗ storage.rules se pasa del límite por ${st - LIMIT} bytes.\n` +
          `  Hay que empezar a strippearlo también (ver firebase.json).`,
      );
      failed = true;
    } else if (st > LIMIT * WARN_RATIO) {
      console.warn(`\n⚠ storage.rules está al ${pct(st)} del límite.`);
    }
  }

  if (failed) process.exit(1);

  if (!checkOnly) {
    fs.writeFileSync(OUTPUT, stripped);
    console.log(`\n✓ escrito ${path.relative(ROOT, OUTPUT)}`);
  }
}

main();
