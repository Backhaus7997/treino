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

const { parseArgs, reglasDePerfilesConocenElCampo } =
  require('../set_trainer_discovery_visibility');

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
