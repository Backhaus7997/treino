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
 * 2. Credenciales (#834). La clave NO va adentro del repo: se guarda afuera y
 *    la ruta sale de `$TREINO_SA_KEY`. Toda ruta adentro de un árbol de git
 *    —incluido cualquier worktree— se rechaza.
 *      mkdir -p ~/.config/treino && chmod 600 ~/.config/treino/sa-key.json
 *      export TREINO_SA_KEY="~/.config/treino/sa-key.json"
 *    Detalle y migración: scripts/README.md → "Credenciales (#834)".
 *
 * 3. Run:
 *      node scripts/backfill_user_public_profiles.js
 *
 *    Against the local emulator no key is needed:
 *      FIRESTORE_EMULATOR_HOST=localhost:8080 \
 *      node scripts/backfill_user_public_profiles.js
 *
 * 4. Verify: check logs for "Backfill complete" and spot-check a few
 *    userPublicProfiles docs in the Firebase Console.
 *
 * ────────────────────────────────────────────────────────────────────────────
 * SAFETY
 * ────────────────────────────────────────────────────────────────────────────
 * - Uses {merge: true} AND omits every key the users/{uid} doc doesn't have.
 *   Both halves matter: merge only preserves keys ABSENT from the payload, so
 *   sending `avatarUrl: null` would still wipe an existing public avatar.
 *   Absent private field → key omitted → existing public value untouched.
 * - Never deletes a public field. Clearing one is a deliberate, separate op.
 * - Logs progress every 100 documents.
 * - Halts on any Firestore error — fix the error and re-run (idempotent).
 * - Processes users in batches of 500 (Firestore WriteBatch limit).
 * ────────────────────────────────────────────────────────────────────────────
 */

'use strict';

// Credenciales: la única puerta (#834). Sin `$TREINO_SA_KEY` esto falla cerrado
// con la migración; contra el emulador no pide nada. Ver scripts/lib/admin.js.
const { inicializarAdmin } = require('./lib/admin');

const { admin } = inicializarAdmin();

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
      const displayName = data.displayName;

      // Only include keys the source `users/{uid}` doc actually has.
      // `{merge: true}` preserves keys that are ABSENT from the payload — it
      // does NOT protect a key written as `null`. Building the object with
      // all 5 keys always present therefore clobbered an existing public
      // `avatarUrl`/`gymId`/`displayName` whenever the private doc lacked it.
      const publicData = { uid };
      if (displayName !== undefined && displayName !== null) {
        publicData.displayName = displayName;
        publicData.displayNameLowercase =
          typeof displayName === 'string'
            ? displayName.trim().toLowerCase()
            : null;
      }
      if (data.avatarUrl !== undefined && data.avatarUrl !== null) {
        publicData.avatarUrl = data.avatarUrl;
      }
      if (data.gymId !== undefined && data.gymId !== null) {
        publicData.gymId = data.gymId;
      }

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
