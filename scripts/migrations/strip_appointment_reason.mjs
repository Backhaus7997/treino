#!/usr/bin/env node
/**
 * Migración #846 — saca la clave `reason` de primer nivel de `appointments`.
 *
 * ⚠️ ESTE SCRIPT NO SE CORRIÓ. Escribe en producción y por eso queda escrito y
 * escalado, no ejecutado. Ver el final de este comentario.
 *
 * ─── Qué arregla ────────────────────────────────────────────────────────────
 *
 * `functions/src/cascade/appointments.ts` escribía, con Admin SDK:
 *
 *     batch.update(doc.ref, { status: "cancelled", reason: "athlete-account-deleted" });
 *
 * `reason` NO existe en `Appointment.toJson()` ni en las 14 claves de
 * `hasOnly()` de `appointmentShapeOk()` / `appointmentUpdateShapeOk()` en
 * `firestore.rules` — sólo existe DENTRO de `CancellationEntry`, que es un
 * elemento del `cancellationLog`.
 *
 * El Admin SDK saltea las reglas, así que la escritura pasaba. El daño es lo
 * que queda después: `hasOnly()` corre sobre `request.resource.data`, que es el
 * documento **MERGEADO**, así que cualquier update PARCIAL posterior del
 * cliente arrastra el `reason` guardado y la allowlist lo rechaza. Medido
 * contra el emulador (`appointments-shape-rules.test.ts`, bloque #846):
 *
 *   · el PF anota un turno que lleva `reason`   → DENY
 *   · el atleta cancela un turno con `reason`   → DENY
 *   · borrar el turno                           → DENY (`allow delete: if false`)
 *
 * O sea: turno imborrable, la familia de #781, sembrada por nuestro propio
 * backend.
 *
 * ─── Por qué hace falta una migración y no alcanza el fix de la CF ──────────
 *
 * El fix de la CF (mover el motivo adentro del `cancellationLog`) evita turnos
 * NUEVOS congelados. **No destraba los que ya se escribieron**: la clave sigue
 * guardada en esos documentos y `hasOnly()` mira el merge, no la escritura.
 * Está medido en el mismo bloque de tests: el caso "sacando la clave con Admin
 * SDK el mismo turno se cancela" es exactamente lo que hace este script.
 *
 * El motivo NO se pierde: se reescribe como una entrada de `cancellationLog`,
 * que es el rastro de auditoría real de la colección y sí está en la allowlist.
 *
 * ─── Urgencia ───────────────────────────────────────────────────────────────
 *
 * Baja, y conviene que esté escrito. Los turnos que la CF tocó ya están
 * `cancelled` y su atleta fue borrado, así que hoy nadie los edita. Lo que la
 * migración recupera es el invariante —"el cliente siempre puede cancelar lo
 * suyo"— y el margen de que la CF cambie y la clave llegue a un doc
 * `confirmed`.
 *
 * ─── Uso ────────────────────────────────────────────────────────────────────
 *
 *   export GOOGLE_APPLICATION_CREDENTIALS="$TREINO_SA_KEY"   # ~/.config/treino/sa-key.json
 *   node scripts/migrations/strip_appointment_reason.mjs --project=<id>            # DRY-RUN
 *   node scripts/migrations/strip_appointment_reason.mjs --project=<id> --apply \
 *        --si-escribo-en-produccion                                               # escribe
 *
 * Sin `--apply` no escribe nada: cuenta los documentos afectados y muestra los
 * primeros. `treino-dev` **ES** producción (#826), así que el `--apply` va con
 * una decisión humana atrás, no dentro de una sesión de agente.
 *
 * ─── Y por qué el destino se ANUNCIA antes de escribir ──────────────────────
 *
 * Lo marcó la review de Codex sobre este mismo PR, y tiene razón: la primera
 * versión hacía `initializeApp()` sin resolver ni mostrar el destino, y omitir
 * `--project` deja que el SDK lo elija desde las credenciales del ambiente. O
 * sea que una invocación copiada podía reescribir turnos de producción
 * mostrando en pantalla nada más que un conteo de documentos. Es exactamente el
 * modo de fallar que #826 vino a cerrar, y para el que ya existen
 * `scripts/lib/firebase_projects.js` y `scripts/lib/target_project.js`.
 *
 * Este script va UN PASO más que la convención del #826, y a propósito. Esa
 * convención es "el operador VE la verdad, pero la decisión de correr o no
 * correr NO cambia", porque cambiarla rompía invocaciones documentadas
 * (`npm run seed:all`, `npm run promote:trainer`). Acá no hay ninguna
 * invocación previa que romper —es una migración de una sola vez—, así que
 * contra producción el `--apply` **falla cerrado** sin el flag explícito. Y si
 * el destino no se puede resolver, tampoco escribe: no saber contra qué
 * proyecto estás no es lo mismo que saber que no es producción.
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
const { usandoEmulador, projectIdObjetivo } = require("../lib/target_project");

const args = process.argv.slice(2);
const projectArg = args.find((a) => a.startsWith("--project="));
const projectId = projectArg ? projectArg.split("=")[1] : undefined;
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
const contraEmulador = usandoEmulador();

console.log("");
console.log(`  destino : ${destino ?? "(no resuelto — lo elige el Admin SDK)"}`);
console.log(`  modo    : ${apply ? "APLICA (escribe)" : "DRY-RUN (no escribe)"}`);
console.log(`  emulador: ${contraEmulador ? "sí" : "no"}`);
console.log("");

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
