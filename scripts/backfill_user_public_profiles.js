/**
 * backfill_user_public_profiles.js
 *
 * Backfill script: copies the 5 public fields (uid, displayName,
 * displayNameLowercase, avatarUrl, gymId) from every `users/{uid}` document
 * into a corresponding `userPublicProfiles/{uid}` document.
 *
 * ────────────────────────────────────────────────────────────────────────────
 * MIGRATION STRATEGY
 * ────────────────────────────────────────────────────────────────────────────
 * PRIMARY — Lazy migration via dual-write (REQ-UPP-009..013):
 *   New sign-ins and profile updates automatically write to BOTH collections
 *   via the WriteBatch in UserRepository. New users never need this script.
 *
 * ESCAPE HATCH — This script (ops-only):
 *   Run ONCE for existing users who signed up before the dual-write was
 *   deployed. Safe to re-run (idempotent via `{merge: true}`).
 *   Never run from client-side code — requires firebase-admin privileges.
 *
 * ────────────────────────────────────────────────────────────────────────────
 * USAGE (from project root)
 * ────────────────────────────────────────────────────────────────────────────
 * 1. Install dependencies:
 *      npm install firebase-admin
 *
 * 2. Download a service account key from Firebase Console → Project Settings
 *    → Service Accounts → Generate new private key. Save as `sa-key.json`.
 *    DO NOT commit sa-key.json (already in .gitignore).
 *
 * 3. Run:
 *      node scripts/backfill_user_public_profiles.js
 *
 * 4. Verify: check logs for "Backfill complete" and spot-check a few
 *    userPublicProfiles docs in the Firebase Console.
 *
 * ────────────────────────────────────────────────────────────────────────────
 * SAFETY
 * ────────────────────────────────────────────────────────────────────────────
 * - Uses {merge: true} — existing fields in userPublicProfiles are NOT
 *   overwritten if the users/{uid} doc is missing a field.
 * - Logs progress every 100 documents.
 * - Halts on any Firestore error — fix the error and re-run (idempotent).
 * - Processes users in batches of 500 (Firestore WriteBatch limit).
 * ────────────────────────────────────────────────────────────────────────────
 */

'use strict';

const admin = require('firebase-admin');

// Adjust the path to your service account key file.
const serviceAccount = require('./sa-key.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

async function backfill() {
  const usersRef = db.collection('users');
  const publicProfilesRef = db.collection('userPublicProfiles');

  let lastDoc = null;
  let processedCount = 0;
  const PAGE_SIZE = 500; // Firestore WriteBatch limit

  console.log('Starting backfill of userPublicProfiles...');

  // eslint-disable-next-line no-constant-condition
  while (true) {
    let query = usersRef.limit(PAGE_SIZE);
    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snapshot = await query.get();
    if (snapshot.empty) break;

    const batch = db.batch();

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const uid = data.uid ?? doc.id;
      const displayName = data.displayName ?? null;
      const publicData = {
        uid,
        displayName,
        displayNameLowercase:
          typeof displayName === 'string'
            ? displayName.trim().toLowerCase()
            : null,
        avatarUrl: data.avatarUrl ?? null,
        gymId: data.gymId ?? null,
      };

      batch.set(publicProfilesRef.doc(uid), publicData, { merge: true });
      processedCount++;
    }

    await batch.commit();

    lastDoc = snapshot.docs[snapshot.docs.length - 1];

    if (processedCount % 100 === 0 || snapshot.docs.length < PAGE_SIZE) {
      console.log(`Processed ${processedCount} users...`);
    }
  }

  console.log(`Backfill complete. Total users processed: ${processedCount}`);
}

backfill().catch((err) => {
  console.error('Backfill FAILED:', err);
  process.exit(1);
});
