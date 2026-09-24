'use strict';

/**
 * scripts/medir_ejercicios_propios.js
 *
 * limite-ejercicios-pf.md, PR 0 — mide cuantos ejercicios propios
 * (`users/{uid}/customExercises`) tiene hoy cada PF, para confirmar que los
 * topes de la escalera 20/60/120/sin-limite no dejan a nadie actual pasado
 * de plan antes de encender `TRAINER_EXERCISE_LIMITS_ENABLED`.
 *
 * SOLO LECTURA. Este script no escribe NADA, en ningun proyecto, nunca.
 *
 * ─── Credenciales y guard (§ Entornos de AGENTS.md) ─────────────────────────
 *
 * Entra por `lib/admin.js` (`inicializarAdmin`, #834): la credencial sale de
 * `$TREINO_SA_KEY` (o de `FIRESTORE_EMULATOR_HOST` contra el emulador), y
 * `treino-dev` ES PRODUCCION — no hay un proyecto de desarrollo separado.
 *
 * Trae ademas el guard `--allow-prod` + el cartel de `lib/firebase_projects.js`,
 * calcado de `backfill_gym_ids.js`/`backfill_gym_names.js`. Es MAS estricto
 * que la convencion de otros scripts de solo-lectura de esta carpeta
 * (`audit_ranking_optin.js` corre directo contra el proyecto real sin ningun
 * guard, porque leer no puede dañar datos). Se suma aca a proposito porque
 * asi lo pide el plan (limite-ejercicios-pf.md, PR0) y porque el resultado de
 * este script decide una migracion de producto real (§5, el aviso a los
 * entrenadores) — vale la pena el paso extra de friccion aunque el script no
 * escriba un solo byte.
 *
 * ─── Simplificacion deliberada: el tier efectivo NO se importa de functions/ ─
 *
 * El plan sugiere reusar la resolucion de tier efectivo del backend
 * (`effectiveTier` en `functions/src/subscriptions/effective-limit.ts`) "si
 * es razonable". No lo es: `functions/` es TypeScript y compila a
 * `functions/lib/` con `tsc`; importar el compilado desde `scripts/`
 * (CommonJS, sin ese paso de build) acoplaria este script a que alguien haya
 * corrido `npm run build` en `functions/` ANTES de correrlo, y fallaria en
 * silencio con un `effectiveTier` viejo si ese build esta desactualizado.
 *
 * Este script REPLICA una version simplificada de esa logica en vez de
 * importarla — mismos cinco casos de status que `effectiveWeightLimit`, pero
 * SIN EL PISO PREPAGO (#1203). Lo que se pierde: un PF que bajo de plan
 * recientemente y todavia conserva el remanente pago de un tier mayor puede
 * aparecer aca con un tope MENOR al que realmente le corresponde — nunca al
 * reves, asi que el sesgo es hacia sobre-contar a quien quedaria "por
 * encima" de su tope, nunca hacia ocultarlo. Con pocos PF (el barrido del
 * 16/09 daba `scanned: 5`) esto se revisa a ojo: si alguien aparece justo en
 * el borde, cruzar a mano contra `subscription.prepaidTier` /
 * `prepaidUntilMs` en su documento antes de mandarle el aviso del §5.
 *
 * La tabla de topes (20/60/120/null) es un LITERAL congelado de
 * `TIER_CUSTOM_EXERCISE_LIMITS` (`functions/src/subscriptions/tier-config.ts`)
 * al momento de escribir este script — mismo motivo: no hay compilado que
 * importar. Si esa tabla cambia, este script queda desactualizado hasta que
 * alguien lo note; no hay nada que lo sincronice automaticamente.
 *
 * ─── Que hace ─────────────────────────────────────────────────────────────
 *
 * Por cada `users` con `role == 'trainer'`: imprime `subscription.tier`,
 * `subscription.status` y la cantidad de `customExercises` (via `.count()` —
 * no descarga los documentos). Al final: mediana, percentil 90, maximo, y la
 * lista de quien quedaria POR ENCIMA de su tope si el interruptor se
 * encendiera hoy.
 *
 * Usage:
 *   # Contra un proyecto real (necesita $TREINO_SA_KEY — ver scripts/README.md):
 *   cd scripts && node medir_ejercicios_propios.js
 *
 *   # Contra el emulador (no pide credencial):
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/medir_ejercicios_propios.js
 *
 *   # Salida machine-readable, para pegar en el issue/PR:
 *   node scripts/medir_ejercicios_propios.js --json
 *
 *   # Solo si el proyecto resuelto no "parece" dev (no aplica hoy: TREINO
 *   # tiene un unico proyecto, treino-dev, y SI "parece" dev por nombre):
 *   node scripts/medir_ejercicios_propios.js --allow-prod
 */

// Credenciales: la unica puerta (#834). Sin `$TREINO_SA_KEY` esto falla
// cerrado con la migracion; contra el emulador no pide nada.
const { inicializarAdmin, proyectoDe } = require('./lib/admin');
const { getFirestore } = require('firebase-admin/firestore');
const { bannerDeProduccion } = require('./lib/firebase_projects');

const { app, contexto } = inicializarAdmin();

const PROJECT_ID = proyectoDe(contexto);
const USANDO_EMULADOR = contexto.modo === 'emulador';

const db = getFirestore(app);

const asJson = process.argv.includes('--json');
const allowProd = process.argv.includes('--allow-prod');

/**
 * Literal congelado de `TIER_CUSTOM_EXERCISE_LIMITS`
 * (`functions/src/subscriptions/tier-config.ts`). Ver el encabezado: no hay
 * compilado que importar desde `scripts/`.
 */
const TIER_CUSTOM_EXERCISE_LIMITS = { free: 20, plan1: 60, plan2: 120, plan3: null };

/**
 * Imprime el proyecto destino y decide si seguir. Mismo guard —mismos exit
 * codes— que `backfill_gym_ids.js`: no protege contra `treino-dev` (contiene
 * "dev"), solo contra un proyecto INESPERADO. Ver AGENTS.md §11.1: ese guard
 * es conocido por no alcanzar solo, y el cartel de abajo es la mitigacion
 * real.
 */
function assertDevProject() {
  console.log(`Target Firebase project: ${PROJECT_ID}`);

  const banner = bannerDeProduccion(PROJECT_ID, { contraEmulador: USANDO_EMULADOR });
  if (banner) console.warn(banner);

  const looksLikeDev = /dev/i.test(String(PROJECT_ID));
  if (!looksLikeDev && !allowProd) {
    console.error(
      `\nREFUSING TO RUN: project_id "${PROJECT_ID}" does not look like a ` +
        'dev project. Re-run with --allow-prod if this is intentional.',
    );
    process.exit(1);
  }
  if (!looksLikeDev && allowProd) {
    console.warn(`\n⚠ --allow-prod passed. Proceeding against "${PROJECT_ID}".\n`);
  }
}

/** El tier saneado contra la tabla conocida. Un tier ausente/roto → free. */
function tierNominal(tier) {
  return Object.prototype.hasOwnProperty.call(TIER_CUSTOM_EXERCISE_LIMITS, tier)
    ? tier
    : 'free';
}

/** Millis de un valor que DEBERIA ser un Timestamp, sin confiar en que lo sea. */
function toMillis(raw) {
  if (raw == null) return null;
  if (typeof raw.toMillis === 'function') {
    const ms = raw.toMillis();
    return typeof ms === 'number' && Number.isFinite(ms) ? ms : null;
  }
  return null;
}

/**
 * Tier efectivo SIMPLIFICADO (sin piso prepago — ver el encabezado). Mismos
 * cinco casos que `limiteDelStatus` en `effective-limit.ts`:
 *   - sin mapa `subscription` → free
 *   - active/grace → el tier nominal
 *   - cancelled → el tier nominal si `currentPeriodEnd` todavia no vencio,
 *     si no free
 *   - pending/paused/cualquier otra cosa → free
 */
function effectiveTierSimplificado(sub, nowMs) {
  if (!sub || typeof sub !== 'object') return 'free';
  const tier = tierNominal(sub.tier);
  switch (sub.status) {
    case 'active':
    case 'grace':
      return tier;
    case 'cancelled': {
      const endMs = toMillis(sub.currentPeriodEnd);
      return endMs != null && nowMs < endMs ? tier : 'free';
    }
    default:
      return 'free';
  }
}

function median(nums) {
  if (nums.length === 0) return null;
  const sorted = [...nums].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0
    ? (sorted[mid - 1] + sorted[mid]) / 2
    : sorted[mid];
}

/** Percentil por nearest-rank, suficiente para un puñado de PF. */
function percentile(nums, p) {
  if (nums.length === 0) return null;
  const sorted = [...nums].sort((a, b) => a - b);
  const idx = Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1);
  return sorted[Math.max(0, idx)];
}

(async () => {
  assertDevProject();

  const nowMs = Date.now();

  const trainersSnap = await db.collection('users').where('role', '==', 'trainer').get();

  const filas = [];
  for (const doc of trainersSnap.docs) {
    const data = doc.data();
    const sub = data.subscription;
    const tier = tierNominal(sub && sub.tier);
    const status = sub && typeof sub.status === 'string' ? sub.status : '(sin suscripcion)';
    const effectiveTier = effectiveTierSimplificado(sub, nowMs);
    const limit = TIER_CUSTOM_EXERCISE_LIMITS[effectiveTier];

    const countSnap = await db.collection(`users/${doc.id}/customExercises`).count().get();
    const count = countSnap.data().count;

    filas.push({
      uid: doc.id,
      displayName: typeof data.displayName === 'string' ? data.displayName : null,
      email: typeof data.email === 'string' ? data.email : null,
      tier,
      status,
      effectiveTier,
      limit,
      count,
      atOrOverLimit: limit != null && count >= limit,
      overLimit: limit != null && count > limit,
    });
  }

  const counts = filas.map((f) => f.count);
  const resumen = {
    projectId: USANDO_EMULADOR ? `${PROJECT_ID} (EMULATOR)` : PROJECT_ID,
    scanned: filas.length,
    median: median(counts),
    p90: percentile(counts, 90),
    max: filas.length ? Math.max(...counts) : null,
    overLimit: filas.filter((f) => f.overLimit).map((f) => ({
      uid: f.uid,
      email: f.email,
      tier: f.effectiveTier,
      limit: f.limit,
      count: f.count,
    })),
    atLimit: filas.filter((f) => f.atOrOverLimit && !f.overLimit).map((f) => ({
      uid: f.uid,
      email: f.email,
      tier: f.effectiveTier,
      limit: f.limit,
      count: f.count,
    })),
  };

  if (asJson) {
    console.log(JSON.stringify({ ...resumen, filas }, null, 2));
    return;
  }

  console.log('');
  console.log('ejercicios propios por PF — limite-ejercicios-pf.md, PR 0');
  console.log(`project: ${resumen.projectId}`);
  console.log('');
  console.log('  uid                            tier    status       effTier  count  limit');
  console.log('  ' + '-'.repeat(78));
  for (const f of filas) {
    const marca = f.overLimit ? ' ⚠ OVER' : f.atOrOverLimit ? ' AT LIMIT' : '';
    console.log(
      `  ${f.uid.padEnd(30)} ${f.tier.padEnd(7)} ${f.status.padEnd(12)} ` +
        `${f.effectiveTier.padEnd(8)} ${String(f.count).padStart(5)}  ` +
        `${String(f.limit === null ? '—' : f.limit).padStart(5)}${marca}`,
    );
  }
  console.log('');
  console.log(`  PF escaneados ......... ${resumen.scanned}`);
  console.log(`  mediana ................ ${resumen.median ?? '—'}`);
  console.log(`  percentil 90 ........... ${resumen.p90 ?? '—'}`);
  console.log(`  maximo ................. ${resumen.max ?? '—'}`);
  console.log('');
  if (resumen.overLimit.length === 0) {
    console.log('  Nadie quedaria POR ENCIMA de su tope si se encendiera hoy.');
  } else {
    console.log(`  POR ENCIMA de su tope (${resumen.overLimit.length}) — destinatarios del aviso del §5:`);
    for (const r of resumen.overLimit) {
      console.log(`    - ${r.uid}  ${r.email ?? '(sin email)'}  tier=${r.tier}  ${r.count}/${r.limit}`);
    }
  }
  if (resumen.atLimit.length > 0) {
    console.log('');
    console.log(`  EN el tope, justo (${resumen.atLimit.length}) — no crean mas, pero no pierden nada:`);
    for (const r of resumen.atLimit) {
      console.log(`    - ${r.uid}  ${r.email ?? '(sin email)'}  tier=${r.tier}  ${r.count}/${r.limit}`);
    }
  }
  console.log('');
  console.log('  Ver el encabezado de este script: la simplificacion (sin piso prepago)');
  console.log('  sesga hacia SOBRE-contar a quien queda "por encima", nunca al reves.');
  console.log('');
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
