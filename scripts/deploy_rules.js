/**
 * deploy_rules.js
 *
 * Deploys `../firestore.rules` to the active Firestore database using the
 * Firebase Rules REST API + la credencial que resuelve `lib/credenciales.js`.
 *
 * No usa `firebase-admin`: `GoogleAuth` se autentica solo. Por eso pasa por el
 * resolutor DIRECTAMENTE y no por `lib/admin.js` (#834). Y por eso mismo era el
 * más fácil de dejar afuera: no hace `require('./sa-key.json')` ni menciona
 * `GOOGLE_APPLICATION_CREDENTIALS`, así que ninguno de los dos greps con los que
 * se midió el problema lo encontraba. Leía `scripts/sa-key.json` por ruta.
 *
 * Why this exists: Firebase CLI requires interactive auth; the team has not
 * re-authenticated locally, so we deploy via the REST API directly.
 *
 * 🚨 ESCRIBE EN PRODUCCIÓN, y por un camino que ningún default frena (#826).
 * El proyecto NO sale de `.firebaserc` ni de `firebase use` ni de `--project`:
 * sale del `project_id` del service account (línea ~30) y pega contra la REST
 * API de Firebase Rules. `FIRESTORE_EMULATOR_HOST` tampoco lo desvía. Publicar
 * rules pega al instante en todas las apps ya instaladas.
 *
 * Usage:
 *   cd scripts && node deploy_rules.js
 */

'use strict';

const fs = require('fs');
const path = require('path');
const { GoogleAuth } = require('google-auth-library');
const { bannerDeProduccion } = require('./lib/firebase_projects');

const { ErrorDeCredencial, cargarCredencial } = require('./lib/credenciales');

const RULES_PATH = path.join(__dirname, '..', 'firestore.rules');

/** Este script SIEMPRE escribe en un proyecto real: no hay camino de emulador. */
function credencial() {
  try {
    const { credencial: cred, avisos } = cargarCredencial();
    for (const aviso of avisos) console.error(aviso);
    return cred;
  } catch (err) {
    if (!(err instanceof ErrorDeCredencial)) throw err;
    console.error(err.message);
    process.exit(1);
  }
}

(async () => {
  const sa = credencial();
  const projectId = sa.project_id;

  // Este script IGNORA `.firebaserc`, `firebase use` y `--project`: el destino
  // sale del `project_id` del service account y va derecho contra la REST API
  // de Firebase Rules. O sea que ningún cambio de default del CLI lo frena, y
  // ni `FIRESTORE_EMULATOR_HOST` lo desvía — de ahí que el cartel no lleve
  // `contraEmulador`: acá no existe el modo emulador. (#826)
  const bannerProd = bannerDeProduccion(projectId);
  if (bannerProd) console.warn(bannerProd);

  const rulesContent = fs.readFileSync(RULES_PATH, 'utf8');
  console.log(`Project: ${projectId}`);
  console.log(`Rules file: ${RULES_PATH}`);
  console.log(`Rules size: ${rulesContent.length} bytes\n`);

  // `credentials` y no `keyFile`: la clave ya está leída y validada; no queremos
  // una segunda ruta al filesystem que se saltee la frontera.
  const auth = new GoogleAuth({
    credentials: sa,
    scopes: ['https://www.googleapis.com/auth/firebase'],
  });
  const client = await auth.getClient();

  // ── Step 1: GET currently active ruleset to compare ────────────────────────
  console.log('── Step 1: Fetch currently deployed rules ──');
  const releaseUrl = `https://firebaserules.googleapis.com/v1/projects/${projectId}/releases/cloud.firestore`;
  const releaseRes = await client.request({ url: releaseUrl });
  const activeRulesetName = releaseRes.data.rulesetName;
  console.log(`Active ruleset: ${activeRulesetName}`);

  const rulesetRes = await client.request({
    url: `https://firebaserules.googleapis.com/v1/${activeRulesetName}`,
  });
  const deployedSource = rulesetRes.data.source.files[0].content;
  console.log(`Deployed rules size: ${deployedSource.length} bytes`);

  if (deployedSource === rulesContent) {
    console.log('\n✓ Deployed rules ALREADY MATCH local file. No deploy needed.');
    console.log('  → The bug is NOT a stale rules deployment.');
    return;
  }

  console.log('\n⚠️  Deployed rules DIFFER from local file. Deploying now...\n');

  // ── Step 2: Create new ruleset ─────────────────────────────────────────────
  const createRes = await client.request({
    url: `https://firebaserules.googleapis.com/v1/projects/${projectId}/rulesets`,
    method: 'POST',
    data: {
      source: {
        files: [{ name: 'firestore.rules', content: rulesContent }],
      },
    },
  });
  const newRulesetName = createRes.data.name;
  console.log(`✓ Created new ruleset: ${newRulesetName}`);

  // ── Step 3: Update release to point to new ruleset ─────────────────────────
  await client.request({
    url: `https://firebaserules.googleapis.com/v1/projects/${projectId}/releases/cloud.firestore`,
    method: 'PATCH',
    data: {
      release: {
        name: `projects/${projectId}/releases/cloud.firestore`,
        rulesetName: newRulesetName,
      },
    },
  });
  console.log(`✓ Activated new ruleset for cloud.firestore`);
  console.log('\n✓ DEPLOY COMPLETE. The rules in the file are now live in Firestore.');
})().catch((err) => {
  console.error('FAILED:', err.message);
  if (err.response?.data) {
    console.error('Response:', JSON.stringify(err.response.data, null, 2));
  }
  process.exit(1);
});
