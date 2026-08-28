/**
 * test/fixtures/probe_admin_import.mjs
 *
 * Sonda mínima para `esm_stub_interception.test.js`: importa `firebase-admin`
 * por los DOS caminos que un `.mjs` de `scripts/migrations/` usa de verdad
 * —`import` (loader ESM) y `createRequire` (Module._load)— y dice cuál de los
 * dos módulos le llegó.
 *
 * No prueba ninguna compuerta: prueba que el STUB sea el que contesta. Sin este
 * archivo, la única señal de que el stub se aplicó es la AUSENCIA de
 * `STUB_FIRESTORE_REACHED`, y esa ausencia también se produce cuando el stub
 * nunca existió. (#846)
 */

import { createRequire } from "node:module";

import adminEsm from "firebase-admin";

const require = createRequire(import.meta.url);

let adminCjs = null;
try {
  adminCjs = require("firebase-admin");
} catch {
  adminCjs = null;
}

console.log(`ESM=${adminEsm?.__stubDeTest === true ? "STUB" : "REAL"}`);
console.log(`CJS=${adminCjs?.__stubDeTest === true ? "STUB" : "REAL"}`);
