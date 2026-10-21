/**
 * test/set_trainer_discovery_visibility.test.js
 *
 * El chequeo de reglas que frena el `--apply`: escribir `hiddenFromDiscovery`
 * en `userPublicProfiles` con reglas desplegadas que no lo conocen deja a esa
 * cuenta sin poder editar su perfil. El campo ya aparece en el bloque de
 * `trainerPublicProfiles`, así que un `includes` sobre el archivo entero
 * diría «conocen» con reglas viejas — eso es lo que fijan estos tests.
 *
 *   node --test scripts/test/
 */

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const { readFileSync } = require('fs');
const path = require('path');

const {
  parseArgs,
  reglasDePerfilesConocenElCampo,
  fuenteDeReglasDesplegadas,
  aplicarVisibilidad,
} = require('../set_trainer_discovery_visibility');

/** Un ref que revienta si alguien le escribe directo, fuera del batch. */
const refFalso = (path) => ({
  path,
  set: () => { throw new Error(`escritura suelta en ${path}`); },
  update: () => { throw new Error(`escritura suelta en ${path}`); },
});

/** db falsa: registra lo que se encola y si se hizo commit. */
function dbFalsa({ commitFalla = false } = {}) {
  const estado = { batches: 0, encolados: [], commits: 0 };
  return {
    estado,
    batch() {
      estado.batches++;
      return {
        update(ref, data) { estado.encolados.push({ path: ref.path, data }); },
        set() { throw new Error('set en el batch: tiene que ser update'); },
        async commit() {
          if (commitFalla) throw new Error('commit rechazado');
          estado.commits++;
        },
      };
    },
  };
}

const LOS_DOS = [
  { coleccion: 'trainerPublicProfiles', ref: refFalso('trainerPublicProfiles/u') },
  { coleccion: 'userPublicProfiles', ref: refFalso('userPublicProfiles/u') },
];

test('aplicarVisibilidad: las dos colecciones en UN batch y un commit', async () => {
  const db = dbFalsa();
  await aplicarVisibilidad(db, LOS_DOS, true);

  assert.strictEqual(db.estado.batches, 1);
  assert.strictEqual(db.estado.commits, 1);
  assert.deepStrictEqual(db.estado.encolados, [
    { path: 'trainerPublicProfiles/u', data: { hiddenFromDiscovery: true } },
    { path: 'userPublicProfiles/u', data: { hiddenFromDiscovery: true } },
  ]);
});

test('aplicarVisibilidad: si el commit falla, propaga y no escribe por fuera', async () => {
  const db = dbFalsa({ commitFalla: true });
  await assert.rejects(aplicarVisibilidad(db, LOS_DOS, false), /commit rechazado/);
  assert.strictEqual(db.estado.commits, 0);
});

test('fuenteDeReglasDesplegadas: junta los archivos del ruleset del SDK', async () => {
  const app = {};
  const reglasDe = (a) => {
    assert.strictEqual(a, app);
    return {
      getFirestoreRuleset: async () => ({
        source: [{ name: 'a.rules', content: 'uno' }, { name: 'b.rules', content: 'dos' }],
      }),
    };
  };
  assert.strictEqual(await fuenteDeReglasDesplegadas(app, { reglasDe }), 'uno\ndos');
});

const REGLAS = readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8');

test('las reglas del repo conocen el campo en userPublicProfiles', () => {
  assert.strictEqual(reglasDePerfilesConocenElCampo(REGLAS), true);
});

test('reglas viejas: el campo sólo en trainerPublicProfiles NO cuenta', () => {
  const inicio = REGLAS.search(/^\s*match \/userPublicProfiles\//m);
  const fin = REGLAS.indexOf('match /trainerPublicProfiles/');
  assert.ok(inicio !== -1 && fin > inicio, 'el control asume userPublicProfiles antes que trainerPublicProfiles');
  const bloqueViejo = REGLAS.slice(inicio, fin).replaceAll("'hiddenFromDiscovery'", "'otro'");
  const viejas = REGLAS.slice(0, inicio) + bloqueViejo + REGLAS.slice(fin);

  assert.ok(viejas.includes("'hiddenFromDiscovery'"), 'el control necesita la mención del PF');
  assert.strictEqual(reglasDePerfilesConocenElCampo(viejas), false);
});

test('sin bloque de userPublicProfiles: no conocen', () => {
  assert.strictEqual(reglasDePerfilesConocenElCampo("match /otra/{x} { 'hiddenFromDiscovery' }"), false);
});

test('parseArgs: dry-run por defecto, --apply explícito', () => {
  assert.strictEqual(parseArgs(['node', 's', '--uid=a', '--hidden=true']).apply, false);
  assert.strictEqual(parseArgs(['node', 's', '--uid=a', '--hidden=true', '--apply']).apply, true);
  assert.throws(() => parseArgs(['node', 's', '--uid=a', '--hidden=si']));
});
