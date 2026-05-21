/**
 * deploy_rules.js
 *
 * Deploys `../firestore.rules` to the active Firestore database using the
 * Firebase Rules REST API + the service-account credential in `sa-key.json`.
 *
 * Why this exists: Firebase CLI requires interactive auth; the team has not
 * re-authenticated locally, so we deploy via the REST API directly.
 *
 * Usage:
 *   cd scripts && node deploy_rules.js
 */

'use strict';

const fs = require('fs');
const path = require('path');
const { GoogleAuth } = require('google-auth-library');

const SERVICE_ACCOUNT_PATH = path.join(__dirname, 'sa-key.json');
const RULES_PATH = path.join(__dirname, '..', 'firestore.rules');

(async () => {
  const sa = JSON.parse(fs.readFileSync(SERVICE_ACCOUNT_PATH, 'utf8'));
  const projectId = sa.project_id;

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
