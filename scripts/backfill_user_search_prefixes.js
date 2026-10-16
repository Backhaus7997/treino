/**
 * backfill_user_search_prefixes.js
 *
 * Completa `userPublicProfiles/{uid}.searchPrefixes` (#1478) en los perfiles
 * que existían antes de la Cloud Function que lo escribe
 * (`functions/src/profile/user-search-prefixes.ts`).
 *
 * La CF ya completa sola cada perfil en su PRÓXIMA escritura (contadores,
 * racha, cambio de nombre…). Este script es para los que no se tocan: sin él,
 * un atleta que no entrena desde hace un mes no aparece en la búsqueda nueva.
 * Mientras tanto la app hace también la búsqueda vieja (prefijo de
 * `displayNameLowercase`), así que nadie queda peor que antes; cuando este
 * backfill haya corrido, un PR aparte saca esa búsqueda vieja.
 *
 * ────────────────────────────────────────────────────────────────────────────
 * ⚠️  ORDEN: reglas → functions → este script. Nunca al revés.
 * ────────────────────────────────────────────────────────────────────────────
 * Las reglas de `userPublicProfiles` validan el doc ENTERO con
 * `keys().hasOnly(...)`. Si este script escribe el campo y las reglas
 * desplegadas todavía no lo conocen, la app no puede volver a editar NINGÚN
 * perfil backfilleado: permission-denied en cada guardado.
 *
 * Por eso, con `--apply` contra un proyecto real, el script LEE las reglas
 * desplegadas (API de Firebase Rules, con la misma credencial) y aborta si no
 * mencionan `searchPrefixes`. No es un cartel: es la verificación. Si no puede
 * leerlas, también aborta.
 *
 * ────────────────────────────────────────────────────────────────────────────
 * USO (desde la raíz del proyecto)
 * ────────────────────────────────────────────────────────────────────────────
 *   export TREINO_SA_KEY="~/.config/treino/sa-key.json"   # ver scripts/README.md (#834)
 *
 *   # DRY-RUN (default): cuenta qué escribiría, no toca nada.
 *   node scripts/backfill_user_search_prefixes.js
 *
 *   # Escribe de verdad:
 *   node scripts/backfill_user_search_prefixes.js --apply
 *
 *   # Contra el emulador no hace falta clave (ni chequeo de reglas: el
 *   # emulador carga las del repo):
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 \
 *     node scripts/backfill_user_search_prefixes.js --apply
 *
 * ────────────────────────────────────────────────────────────────────────────
 * SEGURIDAD
 * ────────────────────────────────────────────────────────────────────────────
 * - Sólo escribe `searchPrefixes`, con `update` (nunca crea un perfil).
 * - Con precondición `lastUpdateTime`: si el perfil cambió entre la lectura y
 *   la escritura, no lo pisa — esa escritura disparó la CF, que lo recalcula.
 * - Idempotente: un perfil que ya tiene lo que debe no se reescribe, así que
 *   se puede volver a correr. Usa la misma decisión que la CF.
 * - Lee de a páginas de 300 por id de documento.
 * ────────────────────────────────────────────────────────────────────────────
 */

'use strict';

const { inicializarAdmin, proyectoDe } = require('./lib/admin');
const { bannerDeProduccion } = require('./lib/firebase_projects');
const { contraEmuladorDe, projectIdObjetivo } = require('./lib/target_project');
const { getFirestore, FieldPath } = require('firebase-admin/firestore');
const { searchPrefixesToWrite } = require('./lib/user_search_terms');

const CAMPO = 'searchPrefixes';
const PAGINA = 300;
/** Códigos gRPC: el doc cambió / se borró después de leerlo. */
const FAILED_PRECONDITION = 9;
const NOT_FOUND = 5;

const RULES_API = 'https://firebaserules.googleapis.com/v1';

/**
 * `true` si el ruleset de Firestore DESPLEGADO en [projectId] nombra [campo]
 * entre comillas simples, que es como aparece en las allowlists `hasOnly`.
 * Tira si no lo puede leer: sin respuesta no se escribe.
 */
async function reglasDesplegadasConocen(
  credential,
  projectId,
  campo = CAMPO,
  { fetchImpl = fetch } = {},
) {
  const { access_token: token } = await credential.getAccessToken();
  const headers = { Authorization: `Bearer ${token}` };

  const release = await fetchImpl(
    `${RULES_API}/projects/${projectId}/releases/cloud.firestore`,
    { headers },
  );
  if (!release.ok) throw new Error(`release de cloud.firestore: HTTP ${release.status}`);
  const { rulesetName } = await release.json();

  const ruleset = await fetchImpl(`${RULES_API}/${rulesetName}`, { headers });
  if (!ruleset.ok) throw new Error(`ruleset ${rulesetName}: HTTP ${ruleset.status}`);
  const { source } = await ruleset.json();
  const fuente = (source?.files ?? []).map((f) => f.content ?? '').join('\n');
  return fuente.includes(`'${campo}'`);
}

async function main() {
  const apply = process.argv.includes('--apply');

  // El cartel ANTES de inicializar nada (AGENTS.md §11.1): `treino-dev` es
  // producción. Se calla sólo si Firestore está desviado al emulador.
  const bannerProd = bannerDeProduccion(projectIdObjetivo(), {
    contraEmulador: contraEmuladorDe(['firestore']),
  });
  if (bannerProd) console.warn(bannerProd);

  const { app, contexto } = inicializarAdmin();
  const db = getFirestore(app);

  const proyecto = contexto ? proyectoDe(contexto) : null;
  console.log(`Target Firebase project: ${proyecto ?? '(app ya inicializada)'}`);
  console.log(apply ? 'MODO APPLY: escribe.' : 'DRY-RUN: no escribe (usá --apply).');

  if (apply && contexto?.modo !== 'emulador') {
    let conocen;
    try {
      conocen = await reglasDesplegadasConocen(app.options.credential, proyecto);
    } catch (err) {
      console.error(
        `✗ No pude leer las reglas desplegadas de ${proyecto}: ${err.message}\n` +
          '  Sin eso no escribo: si las reglas no conocen el campo, ningún perfil\n' +
          '  backfilleado se puede volver a editar desde la app.',
      );
      process.exit(1);
    }
    if (!conocen) {
      console.error(
        `✗ Las reglas DESPLEGADAS en ${proyecto} no conocen '${CAMPO}'.\n` +
          '  Deployá primero las reglas (y después functions) desde main. Ver el\n' +
          '  encabezado de este archivo.',
      );
      process.exit(1);
    }
    console.log(`✓ Las reglas desplegadas ya conocen '${CAMPO}'.`);
  }

  let perfiles = 0;
  let aEscribir = 0;
  let escritos = 0;
  let obsoletos = 0;
  let ultimo = null;

  // eslint-disable-next-line no-constant-condition
  while (true) {
    let q = db.collection('userPublicProfiles').orderBy(FieldPath.documentId()).limit(PAGINA);
    if (ultimo) q = q.startAfter(ultimo);
    const snap = await q.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      perfiles++;
      const wanted = searchPrefixesToWrite(doc.data());
      if (wanted === null) continue;
      aEscribir++;
      if (!apply) continue;
      try {
        await doc.ref.update({ [CAMPO]: wanted }, { lastUpdateTime: doc.updateTime });
        escritos++;
      } catch (err) {
        if (err.code === FAILED_PRECONDITION || err.code === NOT_FOUND) {
          obsoletos++;
          continue;
        }
        throw err;
      }
    }

    ultimo = snap.docs[snap.docs.length - 1];
    console.log(`  … ${perfiles} perfiles leídos, ${aEscribir} a completar`);
  }

  console.log(
    `Perfiles: ${perfiles}. A completar: ${aEscribir}. Escritos: ${escritos}. ` +
      `Cambiaron mientras tanto (los recalcula la CF): ${obsoletos}.`,
  );
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

module.exports = { reglasDesplegadasConocen };
