/**
 * backfill_athlete_counts.js
 *
 * Backfills the denormalized `athleteCount` field on every doc in the
 * `trainerPublicProfiles` collection (#388). The `linkAggregate` Cloud
 * Function keeps the field fresh on every `trainer_links` write going
 * forward, but existing trainers would show the "—" placeholder in the
 * public profile stats row until their NEXT link transition. This script
 * stamps the current count of DISTINCT athletes with an `active` link —
 * the same computation `athleteCountFromLinks` performs in
 * functions/src/link-aggregate.ts.
 *
 * Idempotent: docs whose stored `athleteCount` already matches the
 * recomputed value are skipped. Re-runs write nothing.
 *
 * Usage:
 *   # Production (needs scripts/sa-key.json, gitignored):
 *   cd scripts && node backfill_athlete_counts.js           # writes
 *   cd scripts && node backfill_athlete_counts.js --dry-run # logs only
 *
 *   # Emulator (no credentials — same pattern as seed_emulator_full.js):
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/backfill_athlete_counts.js
 */

'use strict';

const admin = require('firebase-admin');

if (process.env.FIRESTORE_EMULATOR_HOST) {
  // Admin SDK with emulator — no service account needed.
  admin.initializeApp({ projectId: 'treino-dev' });
} else {
  let serviceAccount;
  try {
    serviceAccount = require('./sa-key.json');
  } catch (err) {
    if (err.code !== 'MODULE_NOT_FOUND') throw err;
    console.error(
      '\nERROR: scripts/sa-key.json not found — required to run against production.\n' +
      'Download a service-account key from the Firebase console and save it as\n' +
      'scripts/sa-key.json (gitignored), or target the local emulator instead:\n\n' +
      '  FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/backfill_athlete_counts.js\n',
    );
    process.exit(1);
  }
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

const dryRun = process.argv.includes('--dry-run');

(async () => {
  const profiles = await db.collection('trainerPublicProfiles').get();
  console.log(`Found ${profiles.size} trainerPublicProfiles doc(s).`);
  if (dryRun) console.log('(dry-run: no writes will be issued)');
  console.log('');

  let updated = 0;
  let alreadyOk = 0;

  for (const doc of profiles.docs) {
    const trainerId = doc.id;
    const linksSnap = await db
      .collection('trainer_links')
      .where('trainerId', '==', trainerId)
      .get();

    // Same semantics as athleteCountFromLinks (link-aggregate.ts): DISTINCT
    // athletes with status === 'active'; docId fallback for legacy docs.
    const activeAthletes = new Set();
    for (const link of linksSnap.docs) {
      const data = link.data();
      if (data.status !== 'active') continue;
      activeAthletes.add(data.athleteId ?? link.id);
    }
    const athleteCount = activeAthletes.size;

    if (doc.data().athleteCount === athleteCount) {
      alreadyOk++;
      continue;
    }

    updated++;
    console.log(
      `  → ${trainerId}: athleteCount ${doc.data().athleteCount ?? '(absent)'} → ${athleteCount}`,
    );
    if (!dryRun) {
      await doc.ref.set({ athleteCount }, { merge: true });
    }
  }

  console.log('');
  console.log(
    `Done. ${updated} updated, ${alreadyOk} already correct${dryRun ? ' (dry-run — nothing written)' : ''}.`,
  );
  process.exit(0);
})().catch((err) => {
  console.error('backfill_athlete_counts failed:', err);
  process.exit(1);
});
