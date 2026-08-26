/**
 * deploy_rules.js
 *
 * Deploys `../firestore.rules` to the active Firestore database using the
 * Firebase Rules REST API + the service-account credential in `sa-key.json`.
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

const SERVICE_ACCOUNT_PATH = path.join(__dirname, 'sa-key.json');
const RULES_PATH = path.join(__dirname, '..', 'firestore.rules');

(async () => {
  const sa = JSON.parse(fs.readFileSync(SERVICE_ACCOUNT_PATH, 'utf8'));
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

  const auth = new GoogleAuth({
    keyFile: SERVICE_ACCOUNT_PATH,
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
