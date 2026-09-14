/**
 * test/fixtures/probe_admin_subpath_import.mjs
 *
 * La sonda de `subpath_stub_interception.test.js`. Hermana de
 * `probe_admin_import.mjs`, pero para la SEGUNDA puerta del doble: los subpaths
 * modulares (`firebase-admin/firestore`, `firebase-admin/app`).
 *
 * Importa por los dos caminos que un `.mjs` de `migrations/` usa de verdad
 * —`import` (loader ESM) y `createRequire` (`Module._load`)— y dice cuál de los
 * dos módulos le llegó.
 *
 * ─── Por qué el discriminante es de CONDUCTA y no una bandera ───────────────
 *
 * `probe_admin_import.mjs` distingue stub de real mirando `__stubDeTest`. Acá no
 * alcanza, y meter esa bandera en los módulos modulares sería peor: se
 * convertiría en un `export const __stubDeTest` más, o sea superficie inventada
 * que el SDK real no tiene.
 *
 * Lo que se mide es lo que a los tests de compuerta les importa de verdad: que
 * `getFirestore().collection()` tire `STUB_FIRESTORE_REACHED`. Si el módulo real
 * se coló, tira otra cosa (no hay app inicializada). Probar la bandera diría
 * "cargué el stub"; probar el marcador dice "el camino que los tests miden está
 * cableado", que es la afirmación que hace falta.
 */

import { createRequire } from "node:module";

import { getFirestore } from "firebase-admin/firestore";
import { cert } from "firebase-admin/app";

const require = createRequire(import.meta.url);

/** `.collection()` del doble tira `STUB_FIRESTORE_REACHED`; el real, otra cosa. */
function firestoreEs(modulo) {
  try {
    modulo.getFirestore().collection("sondeo");
    return "SIN_MARCADOR"; // ni tiró: no es ninguno de los dos
  } catch (err) {
    return err.message.includes("STUB_FIRESTORE_REACHED") ? "STUB" : "REAL";
  }
}

/**
 * `cert()` del doble devuelve el mismo objeto que le entra
 * (`adminStub.credential.cert = (sa) => sa`). El real construye una credencial
 * y valida la clave, así que la identidad no se conserva.
 */
function appEs(fnCert) {
  const entrada = { projectId: "sondeo", clientEmail: "s@s.iam.gserviceaccount.com", privateKey: "x" };
  try {
    return fnCert(entrada) === entrada ? "STUB" : "REAL";
  } catch {
    return "REAL"; // el real explota con una private key inventada
  }
}

let cjsFirestore = "NO_CARGO";
try {
  cjsFirestore = firestoreEs(require("firebase-admin/firestore"));
} catch {
  cjsFirestore = "NO_CARGO";
}

console.log(`ESM_FIRESTORE=${firestoreEs({ getFirestore })}`);
console.log(`ESM_APP=${appEs(cert)}`);
console.log(`CJS_FIRESTORE=${cjsFirestore}`);
