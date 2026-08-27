#!/usr/bin/env node
/**
 * Migración #846 — saca la clave `reason` de primer nivel de `appointments`.
 *
 * ⚠️⚠️ ESTE SCRIPT YA NO HACE FALTA, Y NO SE DEBE CORRER. ⚠️⚠️
 *
 * Queda escrito porque su compuerta de escritura es el caso de estudio del
 * issue, y porque borrarlo tiraría los tests que la custodian. Leé la sección
 * "Por qué NO se corre" antes que nada.
 *
 * ─── Qué arreglaba ──────────────────────────────────────────────────────────
 *
 * `functions/src/cascade/appointments.ts` escribe, con Admin SDK:
 *
 *     batch.update(doc.ref, { status: "cancelled", reason: "athlete-account-deleted", … });
 *
 * Cuando este script se escribió, `reason` NO estaba en las claves de
 * `hasOnly()` de `appointmentShapeOk()` / `appointmentUpdateShapeOk()` en
 * `firestore.rules`. El Admin SDK saltea las reglas, así que la escritura
 * pasaba; el daño era lo que quedaba después. `hasOnly()` corre sobre
 * `request.resource.data`, que es el documento **MERGEADO**, así que cualquier
 * update PARCIAL posterior del cliente arrastraba el `reason` guardado y la
 * allowlist lo rechazaba. Medido contra el emulador:
 *
 *   · el PF anota un turno que lleva `reason`   → DENY
 *   · el atleta cancela un turno con `reason`   → DENY
 *   · borrar el turno                           → DENY (`allow delete: if false`)
 *
 * O sea: turno imborrable, la familia de #781, sembrada por nuestro propio
 * backend. Este script sacaba la clave para destrabarlos.
 *
 * ─── Por qué NO se corre ────────────────────────────────────────────────────
 *
 * Porque #846 terminó cerrándose **en las reglas**, no en los datos.
 *
 * `reason` ENTRÓ a las dos allowlists y quedó **pineada en los dos caminos de
 * cliente** (`request.resource.data.get('reason', null) ==
 * resource.data.get('reason', null)`), con `== null` en el `create` y el
 * `delete` ya cerrado. O sea que la clave existe para las reglas —y por eso deja
 * de congelar el documento— pero ningún cliente la puede agregar, cambiar ni
 * borrar. **Los documentos que están en producción se destrabaron solos con el
 * deploy de las reglas.** No hay nada que migrar.
 *
 * Y correrlo sería un RETROCESO. `notify-appointment.ts` usa `reason` de GUARD
 * —si el motivo es el del cascade, no manda la notificación—, y esa clave sirve
 * de señal precisamente porque el cliente no la puede escribir. Este script la
 * borra y deja el motivo sólo adentro del `cancellationLog`, donde **cualquier
 * miembro del turno lo puede forjar**: las reglas no iteran listas. Cambiaría
 * una señal CF-only por una falsificable, que es exactamente el bloqueante que
 * hizo revertir la primera versión del fix.
 *
 * Si algún día vuelve a hacer falta sacar la clave, la pregunta que hay que
 * contestar primero es qué señal lee el guard después.
 *
 * ─── Uso (si alguna vez volviera a aplicar) ─────────────────────────────────
 *
 *   export GOOGLE_APPLICATION_CREDENTIALS="$TREINO_SA_KEY"   # ~/.config/treino/sa-key.json
 *   node scripts/migrations/strip_appointment_reason.mjs --project=<id>            # DRY-RUN
 *   node scripts/migrations/strip_appointment_reason.mjs --project=<id> --apply \
 *        --si-escribo-en-produccion                                               # escribe
 *
 * Sin `--apply` no escribe nada: cuenta los documentos afectados y muestra los
 * primeros. `treino-dev` **ES** producción (#826).
 *
 * ─── La compuerta: por qué lee UN SERVICIO y no "algún emulador" ────────────
 *
 * La primera versión decidía con `usandoEmulador()`, que hacía **OR** entre
 * `FIRESTORE_EMULATOR_HOST` y `FIREBASE_AUTH_EMULATOR_HOST`. Este script
 * escribe SÓLO en Firestore. Medido con `--apply` y una service account falsa:
 *
 *     FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099   (y Firestore NO)
 *       → "emulador: sí", sin cartel 🚨, salteando las DOS puertas del --apply
 *       → destino real: treino-dev, o sea PRODUCCIÓN, escribiendo
 *       → murió recién en el canje del token, y sólo porque la key era falsa
 *
 * Y es la situación de todos los días: esa variable queda exportada de una
 * sesión de `emulator.sh` o la hereda una shell. Es literalmente el modo de
 * fallar de #826, en el script que lo cita como motivo de existir.
 *
 * El OR alcanzaba en #826 porque ahí alimentaba a `bannerDeProduccion()`:
 * apagaba un CARTEL, no cambiaba una decisión, y el peor caso era no gritar.
 * Este script fue el primero en ascenderlo a **compuerta de escritura**, y ahí
 * la pregunta es otra: no "¿hay algún emulador puesto?", sino **"¿está desviado
 * el servicio que voy a ESCRIBIR?"**. `contraEmuladorDe(['firestore'])` la
 * contesta. Es el mismo criterio por servicio de `scripts/lib/storage_target.js`,
 * que hasta aborta el split-brain.
 *
 * La matriz completa de las cinco variables de emulador, corriendo este script
 * de verdad con `--apply`, está en
 * `scripts/test/strip_appointment_reason_gate.test.js`.
 *
 * ─── Y por qué el destino se ANUNCIA antes de escribir ──────────────────────
 *
 * Lo marcó la review de Codex sobre este mismo PR: la primera versión hacía
 * `initializeApp()` sin resolver ni mostrar el destino, y omitir `--project`
 * deja que el SDK lo elija desde las credenciales del ambiente. O sea que una
 * invocación copiada podía reescribir turnos de producción mostrando en
 * pantalla nada más que un conteo de documentos.
 *
 * Este script va UN PASO más que la convención del #826, y a propósito. Esa
 * convención es "el operador VE la verdad, pero la decisión de correr o no
 * correr NO cambia", porque cambiarla rompía invocaciones documentadas
 * (`npm run seed:all`, `npm run promote:trainer`). Acá no hay ninguna
 * invocación previa que romper, así que contra producción el `--apply` **falla
 * cerrado** sin el flag explícito. Y si el destino no se puede resolver,
 * tampoco escribe: no saber contra qué proyecto estás no es lo mismo que saber
 * que no es producción.
 *
 * Idempotente: sólo toca documentos que tienen la clave, y correrlo dos veces
 * deja el mismo resultado.
 */

import { createRequire } from "node:module";

import admin from "firebase-admin";

// Los dos módulos del #826 son CommonJS y viven en `scripts/lib/`. Se cargan
// con `createRequire` en vez de un `import` porque el interop de nombres sobre
// CJS depende del lexer de Node, y acá lo que importa es que el cartel salga —
// no ahorrarse dos líneas.
const require = createRequire(import.meta.url);
const { bannerDeProduccion, esProduccion } = require("../lib/firebase_projects");
const {
  emuladoresActivos,
  contraEmuladorDe,
  projectIdObjetivo,
} = require("../lib/target_project");

// Los servicios que ESTE proceso toca. Es la lista entera: el script hace
// `db.collection(...)` y `batch.commit()`, y nada más. Auth, Storage y RTDB no
// se rozan, así que sus variables de emulador no desvían NI UN write de acá.
const SERVICIOS_QUE_TOCA = ["firestore"];

const args = process.argv.slice(2);
const projectArg = args.find((a) => a.startsWith("--project="));
// `--project=` VACIO cuenta como ausente, no como "proyecto llamado cadena
// vacia". Con `??` un string vacio NO cae al fallback —solo null/undefined lo
// hacen— asi que `destino` quedaba "", la compuerta no lo reconocia como
// produccion, no salia el cartel... y el Admin SDK lo ignoraba y resolvia por
// su cuenta a `treino-dev`. La compuerta miraba un destino y el SDK escribia en
// otro. Es la misma familia de #826: el aviso decia una cosa y el write iba a
// otra.
const projectIdCrudo = projectArg ? projectArg.split("=")[1] : undefined;
const projectId =
  projectIdCrudo && projectIdCrudo.trim() !== "" ? projectIdCrudo.trim() : undefined;
const apply = args.includes("--apply");
const confirmado = args.includes("--si-escribo-en-produccion");

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error(
    "Faltan credenciales de Admin SDK.\n\n" +
      '  export GOOGLE_APPLICATION_CREDENTIALS="$TREINO_SA_KEY"\n\n' +
      "`--project=<id>` sólo elige el proyecto; no autentica nada."
  );
  process.exit(2);
}

// ─── El destino, ANTES de `initializeApp()` y antes del primer write ────────
//
// `--project` gana porque es lo que se le pasa al SDK abajo; si no está, se
// resuelve por las mismas fuentes y en el mismo orden que usa el Admin SDK.
const destino = projectId ?? projectIdObjetivo();

// ─── La compuerta lee EL SERVICIO QUE ESCRIBE ───────────────────────────────
//
// Acá había `usandoEmulador()`, que hace OR entre `FIRESTORE_EMULATOR_HOST` y
// `FIREBASE_AUTH_EMULATOR_HOST`. Este script escribe SÓLO en Firestore, así que
// un `FIREBASE_AUTH_EMULATOR_HOST` suelto —heredado de una sesión de
// `emulator.sh`, que es la situación de todos los días— daba "emulador: sí",
// apagaba el cartel y salteaba las DOS puertas del `--apply` mientras los
// `batch.update` iban a `treino-dev`. Medido con una key falsa: murió recién en
// el canje del token, ya hablándole al Firestore de producción.
//
// El OR alcanzaba en #826 porque ahí alimentaba a `bannerDeProduccion()` — o
// sea apagaba un CARTEL, no cambiaba una decisión. Esta es la primera vez que
// el valor decide si una escritura ocurre, y para eso la pregunta es otra: no
// "¿hay algún emulador puesto?", sino "¿está desviado el servicio que voy a
// escribir?". Es el mismo criterio por servicio que ya aplica
// `scripts/lib/storage_target.js`.
const emuladores = emuladoresActivos();
const contraEmulador = contraEmuladorDe(SERVICIOS_QUE_TOCA);

// Los OTROS emuladores puestos, que no desvían nada de lo que este script hace.
// Se nombran a propósito: son exactamente los que producen la ilusión.
const emuladoresIrrelevantes = Object.keys(emuladores).filter(
  (s) => emuladores[s] && !SERVICIOS_QUE_TOCA.includes(s),
);

console.log("");
console.log(`  destino : ${destino ?? "(no resuelto — lo elige el Admin SDK)"}`);
console.log(`  modo    : ${apply ? "APLICA (escribe)" : "DRY-RUN (no escribe)"}`);
console.log(`  escribe : ${SERVICIOS_QUE_TOCA.join(", ")}`);
console.log(`  emulador: Firestore=${emuladores.firestore ? "sí" : "no"}` +
  `  ·  Auth=${emuladores.auth ? "sí" : "no"}` +
  `  ·  Storage=${emuladores.storage ? "sí" : "no"}` +
  `  ·  RTDB=${emuladores.database ? "sí" : "no"}`);
console.log("");

if (emuladoresIrrelevantes.length > 0 && !contraEmulador) {
  console.warn(
    `⚠️  Tenés el emulador de ${emuladoresIrrelevantes.join(" y ")} puesto, ` +
      "pero NO el de Firestore.\n" +
      "⚠️  Este script escribe SÓLO en Firestore: esas variables no desvían nada.\n" +
      "⚠️  El destino de abajo es real.\n",
  );
}

const bannerProd = bannerDeProduccion(destino, { contraEmulador });
if (bannerProd) console.warn(bannerProd);

if (apply && !contraEmulador) {
  if (destino === null) {
    console.error(
      "No se puede resolver contra qué proyecto se va a escribir, y esto ESCRIBE.\n" +
        "Pasá `--project=<id>` explícito. No saber si es producción NO es saber\n" +
        "que no lo es (#826)."
    );
    process.exit(2);
  }
  if (esProduccion(destino) && !confirmado) {
    console.error(
      `"${destino}" es PRODUCCIÓN y falta la confirmación explícita.\n\n` +
        "  … --apply --si-escribo-en-produccion\n\n" +
        "Es una migración de una sola vez sobre turnos de usuarios reales."
    );
    process.exit(2);
  }
}

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  ...(projectId ? { projectId } : {}),
});

const db = admin.firestore();
const BATCH_SIZE = 400;

// No hay índice por "tiene tal campo": Firestore no consulta por presencia de
// clave. El barrido es completo y el filtro va en memoria. La colección es
// chica (un turno por sesión agendada) y esto se corre UNA vez.
const snap = await db.collection("appointments").get();
const afectados = snap.docs.filter((d) => d.get("reason") !== undefined);

console.log(`appointments totales:      ${snap.size}`);
console.log(`con \`reason\` de 1er nivel: ${afectados.length}`);

if (afectados.length === 0) {
  console.log("Nada que hacer.");
  process.exit(0);
}

for (const d of afectados.slice(0, 10)) {
  console.log(
    `  ${d.id}  status=${d.get("status")}  reason=${JSON.stringify(d.get("reason"))}`
  );
}
if (afectados.length > 10) {
  console.log(`  … y ${afectados.length - 10} más`);
}

if (!apply) {
  console.log("\nDRY-RUN — no se escribió nada. Agregá --apply para migrar.");
  process.exit(0);
}

let migrados = 0;
for (let i = 0; i < afectados.length; i += BATCH_SIZE) {
  const chunk = afectados.slice(i, i + BATCH_SIZE);
  const batch = db.batch();
  for (const d of chunk) {
    const motivo = d.get("reason");
    const update = {
      reason: admin.firestore.FieldValue.delete(),
    };
    // El motivo no se tira: se reescribe donde el modelo y la allowlist SÍ lo
    // aceptan. `byUid` es el atleta del turno, que es de quien salió la baja
    // que disparó el cascade; `atMs` no se puede reconstruir —la escritura
    // original no lo guardó— así que se usa el `cancelledAt` si está, y si no
    // el momento de la migración.
    if (typeof motivo === "string" && motivo.length > 0) {
      const cancelledAt = d.get("cancelledAt");
      const atMs =
        cancelledAt && typeof cancelledAt.toMillis === "function"
          ? cancelledAt.toMillis()
          : Date.now();
      update.cancellationLog = admin.firestore.FieldValue.arrayUnion({
        byUid: d.get("athleteId") ?? "unknown",
        atMs,
        reason: motivo,
      });
    }
    batch.update(d.ref, update);
  }
  await batch.commit();
  migrados += chunk.length;
  console.log(`  migrados ${migrados}/${afectados.length}`);
}

console.log(`\nListo: ${migrados} turnos destrabados.`);
