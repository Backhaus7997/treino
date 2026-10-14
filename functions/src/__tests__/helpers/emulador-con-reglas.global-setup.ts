/**
 * globalSetup de jest: que el emulador de Firestore NO haya arrancado en
 * allow-all.
 *
 * ─── El agujero ─────────────────────────────────────────────────────────────
 *
 * Desde el #1132 `firebase.json` le hace cargar al emulador
 * `firestore.deploy.rules`, un archivo GENERADO por `scripts/strip_rules.js` y
 * gitignoreado. Si falta, el emulador no falla: avisa "will default to
 * allowing all reads and writes" y arranca sin reglas.
 *
 * El job `functions-test` de CI no lo generaba. Medido sobre `develop` (run
 * 38458054418): el warning está en el log, y la suite da 177/177 en verde
 * igual. Los dos tests REST del reloj (`watch-rest-*-rules.test.ts`) le pegan
 * al namespace `treino-dev` sin cargar reglas propias, y pasaban porque tres
 * suites de Storage (`chat-media-`, `session-feedback-` y
 * `custom-exercise-videos-storage-rules`) cargan `firestore.rules` en ese
 * mismo namespace y jest las corría ANTES. Solos contra el emulador recién
 * levantado: 6 de 14 en rojo (`Expected: 403`, `Received: 200`).
 *
 * O sea: sacar el paso que genera el archivo no ponía NADA en rojo.
 *
 * ─── Por qué un globalSetup y no un chequeo adentro de esos tests ───────────
 *
 * Adentro de los tests el chequeo llega tarde: para cuando corren, otra suite
 * ya pudo haber cargado reglas y el sondeo da 403 aunque el emulador haya
 * arrancado abierto — es justo lo que tapaba el agujero. El globalSetup corre
 * una sola vez, antes de la primera suite, así que mide el estado con el que
 * arrancó el emulador y no el que le dejó el orden de jest.
 *
 * ─── Qué prueba y qué no ────────────────────────────────────────────────────
 *
 * Lee sin auth un documento que ninguna regla matchea. Con reglas: 403 ("No
 * matching allow statements"). En allow-all: 404. Prueba que en el namespace
 * que miden los tests del reloj HAY reglas, y que niegan por defecto.
 *
 * NO prueba que sean las de este `firestore.rules`: un `firestore.deploy.rules`
 * viejo, de otra corrida, pasa igual. En CI no puede pasar porque el job lo
 * regenera en cada run.
 *
 * Sólo sondea si `FIRESTORE_EMULATOR_HOST` está seteada, que es lo que hace
 * `firebase emulators:exec`. Un `npx jest` de unit tests sin emulador no se
 * entera.
 */

// No puede empezar y terminar con doble guión bajo: Firestore reserva esos ids
// y contesta 400 con o sin reglas, así que el sondeo no distinguiría nada
// (medido: `__sondeo_reglas__/x` → 400 en los dos estados).
const SONDEO = "sondeo-de-reglas/sin-auth";

export default async function emuladorConReglas(): Promise<void> {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  if (host === undefined || host === "") return;

  // El mismo namespace, resuelto igual, que los tests REST del reloj.
  const proyecto =
    process.env.GCLOUD_PROJECT ?? process.env.FIREBASE_PROJECT ?? "treino-dev";
  const url =
    `http://${host}/v1/projects/${proyecto}/databases/(default)/documents/${SONDEO}`;

  let status: number;
  try {
    status = (await fetch(url)).status;
  } catch (error) {
    throw new Error(
      `No pude sondear las reglas del emulador de Firestore en ${host}: ${String(error)}`,
      {cause: error},
    );
  }

  if (status === 403) return;

  if (status === 404 || status === 200) {
    throw new Error([
      `El emulador de Firestore arrancó SIN reglas (allow-all) en "${proyecto}":`,
      `una lectura anónima de ${SONDEO} devolvió ${status} en vez de 403.`,
      "",
      "firebase.json le hace cargar firestore.deploy.rules, que es GENERADO y",
      "está gitignoreado. Generalo antes de levantar el emulador:",
      "",
      "  node scripts/strip_rules.js",
    ].join("\n"));
  }

  throw new Error(
    `El sondeo de reglas del emulador devolvió ${status}; se esperaba 403 ` +
    `(reglas cargadas) o 404 (allow-all). No sé en qué estado arrancó: ${url}`,
  );
}
