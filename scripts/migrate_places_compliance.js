'use strict';

/**
 * migrate_places_compliance.js
 *
 * Política de Places (#1338), PR 4 de 5. Limpia lo que ya estaba guardado
 * antes de que el código nuevo dejara de guardar contenido de Google.
 *
 * Qué hace (decisión del dueño 2026-10-06, `decision/places-compliance-gym-names`):
 *
 *   1. `gyms` con `source == 'google-places'` y SIN `coordsFetchedAt` (los
 *      anteriores al cambio; los nuevos siempre lo traen, así que el nombre de
 *      un gym que ya nombró un usuario NUNCA se pisa):
 *        - `name`  -> "Gimnasio" (el mismo placeholder de la cuarentena,
 *          `GYM_NOMBRE_PENDIENTE`) + `nameNeeded: true`: el próximo usuario que
 *          vincule el gym lo nombra.
 *        - `address` se borra (a TODO gym de Google, nuevo o viejo).
 *        - `coordsFetchedAt = Timestamp(0)` (1970) -> el job `refreshPlacesCoords`
 *          lo refresca en su primera corrida. `placeStatus: 'ok'` si falta.
 *      Los gyms `seed` y `self-service` no se tocan (se cuentan y se informan).
 *
 *   2. `userPublicProfiles.gymName` de los usuarios vinculados a esos gyms: NO
 *      se escribe acá. El trigger `propagateGymNameToProfiles` se dispara con
 *      la escritura del gym del paso 1 (el nombre efectivo pasa de "texto de
 *      Google" a `null` porque queda `nameNeeded`) y los deja en `null`. El
 *      script sólo cuenta los perfiles afectados. `--clear-profile-names` los
 *      pone en `null` también acá, por si el trigger no estuviera desplegado.
 *
 *   3. `users/{uid}.trainerLocations` de los PF:
 *        - lugares tipo `gym` cuyo gym es de Google y no tienen `placeId`:
 *          `placeId = gymId` y `coordsFetchedAt = Timestamp(0)`; se recalcula
 *          `users.trainerLocationsCoordsFetchedAt` (el mismo derivado de
 *          `UserRepository._masViejoCoordsFetchedAt`) y, sólo si el PF dio
 *          consentimiento y ya tiene doc público, se espeja a
 *          `trainerPublicProfiles.trainerLocations`.
 *        - lugares `custom` SIN `placeId`: NO SE TOCAN. Los del Coach Hub que
 *          vinieron de la búsqueda de Google y los del GPS del celular tienen
 *          exactamente la misma forma (`id: custom-<ms>`, `customLabel` de texto
 *          libre, sin marca de origen), y no se puede llamar a Google desde acá
 *          para comparar coordenadas. Adivinar borraría etiquetas legítimas de
 *          los PF. Se informan por cantidad para decidir a mano.
 *
 * Idempotente: una segunda corrida no encuentra nada que cambiar. Escribe en
 * batches de <= 400 operaciones, con precondición `lastUpdateTime` (si el
 * documento cambió entre la lectura y la escritura se saltea y se informa;
 * volver a correr lo resuelve).
 *
 * ────────────────────────────────────────────────────────────────────────────
 * USAGE
 * ────────────────────────────────────────────────────────────────────────────
 *   # DRY-RUN (default) — informa qué cambiaría, no escribe nada:
 *   node scripts/migrate_places_compliance.js
 *
 *   # ⚠️ REAL — ESCRIBE EN PRODUCCIÓN (#826). Sólo con --apply explícito:
 *   node scripts/migrate_places_compliance.js --apply
 *
 *   # Piloto de N documentos por fase:
 *   node scripts/migrate_places_compliance.js --apply --limit=5
 *
 *   # Contra el emulador (sin credencial):
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/migrate_places_compliance.js --project=demo-places
 *
 * Contra un proyecto real necesita `$TREINO_SA_KEY` (#834). `--project` sólo
 * elige el proyecto del EMULADOR; contra uno real debe coincidir con la
 * identidad de la credencial o el script aborta.
 *
 * ORDEN: desplegar `refreshPlacesCoords` -> dry-run -> revisar conteos -> --apply.
 */

const { Timestamp, FieldValue } = require('firebase-admin/firestore');

/** Igual a `GYM_NOMBRE_PENDIENTE` de functions/src/moderation/quarantine-vetted-content.ts. */
const GYM_NOMBRE_PENDIENTE = 'Gimnasio';
const GOOGLE_PLACES = 'google-places';
const EPOCH = Timestamp.fromMillis(0);
const MAX_BATCH_WRITES = 400;
const PAGE_SIZE = 200;
const FAILED_PRECONDITION = 9;

// ── Args ────────────────────────────────────────────────────────────────────

function parseArgs(argv) {
  const out = { apply: false, limit: null, project: null, clearProfileNames: false };
  let dryRun = false;
  for (const arg of argv.slice(2)) {
    if (arg === '--apply') out.apply = true;
    else if (arg === '--dry-run') dryRun = true;
    else if (arg === '--clear-profile-names') out.clearProfileNames = true;
    else if (arg.startsWith('--limit=')) {
      const n = Number(arg.slice('--limit='.length));
      if (!Number.isInteger(n) || n < 1) throw new Error(`--limit inválido: "${arg}"`);
      out.limit = n;
    } else if (arg.startsWith('--project=')) {
      out.project = arg.slice('--project='.length) || null;
    } else {
      throw new Error(`Flag desconocida: "${arg}"`);
    }
  }
  // Ante flags en conflicto gana la que NO escribe.
  if (dryRun) out.apply = false;
  return out;
}

// ── Planes puros ────────────────────────────────────────────────────────────

/**
 * Qué cambiar en un doc de `gyms`, o `null` si no hay nada.
 * @returns {null | {set: object, deleteFields: string[], legacyName: boolean}}
 */
function planGym(data) {
  if (data.source !== GOOGLE_PLACES) return null;

  const set = {};
  const deleteFields = [];
  // Legado: nunca pasó por el código nuevo, así que su `name` vino de Google.
  const legacyName = !('coordsFetchedAt' in data) && data.nameNeeded !== true;

  if (legacyName) {
    set.name = GYM_NOMBRE_PENDIENTE;
    set.nameNeeded = true;
  }
  if (!('coordsFetchedAt' in data)) set.coordsFetchedAt = EPOCH;
  if (data.placeStatus === undefined) set.placeStatus = 'ok';
  if ('address' in data) deleteFields.push('address');

  if (Object.keys(set).length === 0 && deleteFields.length === 0) return null;
  return { set, deleteFields, legacyName };
}

/** Réplica de `UserRepository._masViejoCoordsFetchedAt`. */
function masViejoCoordsFetchedAt(locations) {
  let min = null;
  for (const l of locations) {
    if (!l || l.placeId == null) continue;
    const t = l.coordsFetchedAt;
    if (!(t instanceof Timestamp)) continue;
    if (min === null || t.toMillis() < min.toMillis()) min = t;
  }
  return min;
}

/** Réplica de `UserRepository._publishableLocations`. */
function publicables(locations) {
  return locations.filter((l) => l && l.stale !== true && l.lat != null && l.lng != null);
}

/**
 * Qué cambiar en `users/{uid}.trainerLocations`.
 * @returns {{changed: boolean, locations: object[], min: Timestamp|null, customSinPlaceId: number}}
 */
function planTrainer(data, googleGymIds) {
  const locs = Array.isArray(data.trainerLocations) ? data.trainerLocations : [];
  let changed = false;
  let customSinPlaceId = 0;

  const locations = locs.map((l) => {
    if (!l || typeof l !== 'object') return l;
    if (l.type === 'custom' && l.placeId == null) customSinPlaceId++;
    if (l.type === 'gym' && typeof l.gymId === 'string' && googleGymIds.has(l.gymId)) {
      const next = { ...l };
      if (next.placeId == null) {
        next.placeId = l.gymId;
        changed = true;
      }
      if (!(next.coordsFetchedAt instanceof Timestamp)) {
        next.coordsFetchedAt = EPOCH;
        changed = true;
      }
      return changed ? next : l;
    }
    return l;
  });

  return { changed, locations, min: masViejoCoordsFetchedAt(locations), customSinPlaceId };
}

// ── Escritura en batches ────────────────────────────────────────────────────

/**
 * Cada grupo es una lista de escrituras que se aplican juntas. Se empaquetan en
 * batches de <= 400 operaciones. Si un batch falla por precondición (un doc
 * cambió desde que se leyó), se reintenta grupo por grupo y los que siguen
 * fallando se cuentan como conflictos.
 * @returns {Promise<{escritos: number, conflictos: number}>}
 */
async function commitGrupos(db, grupos) {
  let escritos = 0;
  let conflictos = 0;

  const aplicar = (batch, grupo) => {
    for (const w of grupo) {
      if (w.precondition) batch.update(w.ref, w.data, w.precondition);
      else batch.update(w.ref, w.data);
    }
  };

  let i = 0;
  while (i < grupos.length) {
    const lote = [];
    let ops = 0;
    while (i < grupos.length && ops + grupos[i].length <= MAX_BATCH_WRITES) {
      lote.push(grupos[i]);
      ops += grupos[i].length;
      i++;
    }
    if (lote.length === 0) {
      lote.push(grupos[i++]); // un grupo solo nunca pasa de 2 ops
    }
    try {
      const batch = db.batch();
      for (const g of lote) aplicar(batch, g);
      await batch.commit();
      escritos += lote.length;
    } catch (err) {
      if (err && err.code !== FAILED_PRECONDITION) throw err;
      for (const g of lote) {
        try {
          const batch = db.batch();
          aplicar(batch, g);
          await batch.commit();
          escritos++;
        } catch (e2) {
          if (e2 && e2.code !== FAILED_PRECONDITION) throw e2;
          conflictos++;
        }
      }
    }
  }
  return { escritos, conflictos };
}

// ── Fases ───────────────────────────────────────────────────────────────────

async function migrarGyms(db, opts, out, resultado) {
  const r = resultado.gyms;
  const snap = await db.collection('gyms').get();
  const googleIds = new Set();
  const grupos = [];

  for (const doc of snap.docs) {
    const data = doc.data();
    r.total++;
    if (data.source !== GOOGLE_PLACES) {
      r.noGoogle++;
      continue;
    }
    googleIds.add(doc.id);
    r.google++;
    const plan = planGym(data);
    if (!plan) continue;
    if (opts.limit !== null && r.cambiados >= opts.limit) {
      r.omitidosPorLimit++;
      continue;
    }
    r.cambiados++;
    if (plan.legacyName) {
      r.legacy++;
      resultado.gymsLegacyIds.push(doc.id);
    }
    if (plan.deleteFields.length) r.conAddress++;
    out.log(
      `  ${opts.apply ? '' : '[DRY-RUN] WOULD '}gyms/${doc.id}: ` +
        `${plan.legacyName ? `name "${data.name}" -> "${GYM_NOMBRE_PENDIENTE}" + nameNeeded; ` : ''}` +
        `${plan.deleteFields.length ? 'address borrada; ' : ''}` +
        `${'coordsFetchedAt' in plan.set ? 'coordsFetchedAt=1970' : ''}`,
    );
    const update = { ...plan.set };
    for (const f of plan.deleteFields) update[f] = FieldValue.delete();
    grupos.push([{ ref: doc.ref, data: update, precondition: { lastUpdateTime: doc.updateTime } }]);
  }

  if (opts.apply && grupos.length) {
    const c = await commitGrupos(db, grupos);
    r.conflictos = c.conflictos;
    r.cambiados -= c.conflictos;
  }
  return googleIds;
}

async function perfilesDeGymsLegados(db, opts, out, resultado) {
  const r = resultado.profiles;
  const grupos = [];
  for (const gymId of resultado.gymsLegacyIds) {
    const snap = await db.collection('userPublicProfiles').where('gymId', '==', gymId).get();
    for (const doc of snap.docs) {
      if (doc.get('gymName') == null) continue;
      r.afectados++;
      if (opts.clearProfileNames) {
        out.log(
          `  ${opts.apply ? '' : '[DRY-RUN] WOULD '}userPublicProfiles/${doc.id}: gymName -> null`,
        );
        grupos.push([{ ref: doc.ref, data: { gymName: null } }]);
      }
    }
  }
  if (opts.apply && grupos.length) {
    const c = await commitGrupos(db, grupos);
    r.escritos = c.escritos;
  }
}

async function migrarEntrenadores(db, googleIds, opts, out, resultado) {
  const r = resultado.trainers;
  let cursor = null;
  for (;;) {
    let q = db.collection('users').where('role', '==', 'trainer').orderBy('__name__').limit(PAGE_SIZE);
    if (cursor) q = q.startAfter(cursor);
    const page = await q.get();
    if (page.empty) break;

    const grupos = [];
    for (const doc of page.docs) {
      r.total++;
      const data = doc.data();
      const plan = planTrainer(data, googleIds);
      r.customSinPlaceId += plan.customSinPlaceId;
      if (!plan.changed) continue;
      if (opts.limit !== null && r.cambiados >= opts.limit) {
        r.omitidosPorLimit++;
        continue;
      }
      r.cambiados++;
      out.log(
        `  ${opts.apply ? '' : '[DRY-RUN] WOULD '}users/${doc.id}: lugares de gym con placeId + coordsFetchedAt=1970`,
      );
      const grupo = [
        {
          ref: doc.ref,
          data: {
            trainerLocations: plan.locations,
            trainerLocationsCoordsFetchedAt: plan.min,
          },
          precondition: { lastUpdateTime: doc.updateTime },
        },
      ];
      if (opts.apply && data.trainerLocationConsentAt != null) {
        const pubRef = db.collection('trainerPublicProfiles').doc(doc.id);
        const pub = await pubRef.get();
        if (pub.exists) {
          grupo.push({ ref: pubRef, data: { trainerLocations: publicables(plan.locations) } });
          r.espejados++;
        }
      }
      grupos.push(grupo);
    }

    if (opts.apply && grupos.length) {
      const c = await commitGrupos(db, grupos);
      r.conflictos += c.conflictos;
      r.cambiados -= c.conflictos;
    }
    if (page.size < PAGE_SIZE) break;
    cursor = page.docs[page.docs.length - 1];
  }
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {{apply: boolean, limit: number|null, clearProfileNames?: boolean}} opts
 * @param {{log: Function, warn: Function}} [out]
 */
async function run(db, opts, out = console) {
  const resultado = {
    applied: Boolean(opts.apply),
    gymsLegacyIds: [],
    gyms: {
      total: 0, google: 0, noGoogle: 0, cambiados: 0, legacy: 0,
      conAddress: 0, omitidosPorLimit: 0, conflictos: 0,
    },
    profiles: { afectados: 0, escritos: 0 },
    trainers: {
      total: 0, cambiados: 0, espejados: 0, customSinPlaceId: 0,
      omitidosPorLimit: 0, conflictos: 0,
    },
  };

  out.log('\n[1/3] gyms...');
  const googleIds = await migrarGyms(db, opts, out, resultado);
  out.log('\n[2/3] userPublicProfiles de los gyms con nombre de Google...');
  await perfilesDeGymsLegados(db, opts, out, resultado);
  out.log('\n[3/3] users/{uid}.trainerLocations de los PF...');
  await migrarEntrenadores(db, googleIds, opts, out, resultado);

  const { gyms: g, profiles: p, trainers: t } = resultado;
  const tag = opts.apply ? 'SUMMARY' : 'DRY-RUN SUMMARY';
  out.log('\n──────────────────────────────────────────────');
  out.log(tag);
  out.log('──────────────────────────────────────────────');
  out.log(`gyms totales:                          ${g.total}`);
  out.log(`  de Google:                           ${g.google}`);
  out.log(`  seed / self-service (intactos):      ${g.noGoogle}`);
  out.log(`  ${opts.apply ? 'migrados' : 'a migrar'} (cualquier cambio):         ${g.cambiados}`);
  out.log(`    con nombre de Google -> "${GYM_NOMBRE_PENDIENTE}":   ${g.legacy}`);
  out.log(`    con address a borrar:              ${g.conAddress}`);
  out.log(`perfiles con gymName de Google:        ${p.afectados}` +
    (opts.clearProfileNames ? '' : '  (los limpia el trigger propagateGymNameToProfiles)'));
  out.log(`PF totales:                            ${t.total}`);
  out.log(`  ${opts.apply ? 'migrados' : 'a migrar'}:                            ${t.cambiados}`);
  out.log(`  espejos públicos ${opts.apply ? 'actualizados' : '(sólo con --apply)'}:        ${t.espejados}`);
  out.log(`  lugares custom SIN placeId (NO tocados): ${t.customSinPlaceId}`);
  if (g.omitidosPorLimit || t.omitidosPorLimit) {
    out.log(`omitidos por --limit: gyms ${g.omitidosPorLimit}, PF ${t.omitidosPorLimit}`);
  }
  if (g.conflictos || t.conflictos) {
    out.warn(`⚠ conflictos (el doc cambió durante la corrida; volvé a correr): gyms ${g.conflictos}, PF ${t.conflictos}`);
  }
  if (t.customSinPlaceId > 0) {
    out.warn(
      `\n⚠ ${t.customSinPlaceId} lugar(es) custom sin placeId no se tocaron: los del Coach Hub que vinieron\n` +
        '  de la búsqueda de Google y los del GPS del celular son indistinguibles. Revisalos a mano.',
    );
  }
  out.log(opts.apply
    ? '\nMigración completa. Segura de repetir (idempotente).'
    : '\nDry run completo. Re-correr con --apply para escribir.');
  return resultado;
}

// ── Entrypoint ──────────────────────────────────────────────────────────────

function main() {
  let opts;
  try {
    opts = parseArgs(process.argv);
  } catch (err) {
    console.error(err.message);
    process.exit(1);
  }

  // Credenciales: la única puerta (#834). Ver scripts/lib/admin.js.
  const { inicializarAdmin, proyectoDe } = require('./lib/admin');
  const { getFirestore } = require('firebase-admin/firestore');
  const { bannerDeProduccion } = require('./lib/firebase_projects');

  const emulador = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
  const { app, contexto } = inicializarAdmin(
    emulador && opts.project ? { projectId: opts.project } : {},
  );
  const projectId = opts.project && emulador ? opts.project : proyectoDe(contexto);
  if (opts.project && !emulador && opts.project !== projectId) {
    console.error(
      `--project=${opts.project} no coincide con la identidad de la credencial (${projectId}). Abortando.`,
    );
    process.exit(1);
  }

  console.log(`Target Firebase project: ${projectId}`);
  const banner = bannerDeProduccion(projectId, { contraEmulador: contexto.modo === 'emulador' });
  if (banner) console.warn(banner);
  console.log(
    opts.apply
      ? '--apply: ESCRIBE en Firestore.'
      : 'Modo DRY-RUN (default): no se escribe nada. Usá --apply para escribir.',
  );

  return run(getFirestore(app), opts)
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('FAILED:', err);
      process.exit(1);
    });
}

module.exports = {
  GYM_NOMBRE_PENDIENTE,
  parseArgs,
  planGym,
  planTrainer,
  run,
};

if (require.main === module) main();
