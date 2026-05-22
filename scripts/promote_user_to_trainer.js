/**
 * promote_user_to_trainer.js
 *
 * Promotes an existing Firebase Auth user to `role: trainer` in Firestore.
 *
 * **Why this script exists**: the role is immutable post-signup by convention
 * (CLAUDE.md/AGENTS.md: "Trainers created manually by team via Firebase Admin SDK").
 * Regular signup via the app always creates `role: athlete`. To test
 * trainer-side UI (TrainerCoachView, AthleteDetailScreen, RoutineEditorScreen),
 * we need a trainer account.
 *
 * What it does:
 *   1. Look up the Firebase Auth user by email.
 *   2. Update `users/{uid}` Firestore doc:
 *      - `role: 'trainer'`
 *      - Defaults for trainer fields (bio/specialty/rate) so the account is
 *        also discoverable via Coach Discovery (Etapa 2).
 *   3. Upsert `trainerPublicProfiles/{uid}` with the trainer-specific subset
 *      (consumed by Coach Discovery / TrainerPublicProfileScreen).
 *   4. Upsert `userPublicProfiles/{uid}` with the generic public identity
 *      subset (consumed by ChatScreen, post avatars, search — anywhere that
 *      needs a public displayName/avatar for any user regardless of role).
 *      Without this step, accounts created directly with this script would
 *      show as "Usuario" in chats (collection is null/missing).
 *
 * The script is idempotent — safe to re-run. Re-running on an existing
 * trainer will backfill the userPublicProfiles doc if it was missing.
 *
 * ────────────────────────────────────────────────────────────────────────────
 * USAGE
 * ────────────────────────────────────────────────────────────────────────────
 *   cd scripts
 *   node promote_user_to_trainer.js <email>
 *   # or via npm:
 *   npm run promote:trainer -- <email>
 *
 * Example:
 *   node promote_user_to_trainer.js trainer.test@gmail.com
 *
 * ────────────────────────────────────────────────────────────────────────────
 * REVERSAL
 * ────────────────────────────────────────────────────────────────────────────
 *   To convert back to athlete, run with --revert:
 *   node promote_user_to_trainer.js <email> --revert
 *   This sets role back to 'athlete' AND deletes the trainerPublicProfiles doc.
 */

'use strict';

const admin = require('firebase-admin');
const serviceAccount = require('./sa-key.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

const db = admin.firestore();

const email = process.argv[2];
const revert = process.argv.includes('--revert');

if (!email || email.startsWith('--')) {
  console.error('Usage: node promote_user_to_trainer.js <email> [--revert]');
  console.error('Example: node promote_user_to_trainer.js trainer.test@gmail.com');
  process.exit(1);
}

async function promote() {
  const userRecord = await admin.auth().getUserByEmail(email);
  const uid = userRecord.uid;
  console.log(`✓ Found Auth user: ${userRecord.email} (uid: ${uid})`);

  const userRef = db.collection('users').doc(uid);
  const snap = await userRef.get();
  if (!snap.exists) {
    throw new Error(
      `No Firestore profile at users/${uid}. The user must complete signup + ProfileSetup before being promoted.`,
    );
  }
  const data = snap.data();
  console.log(`  Current role: ${data.role}, displayName: ${data.displayName ?? '(no name)'}`);

  if (revert) {
    await userRef.update({
      role: 'athlete',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await db.collection('trainerPublicProfiles').doc(uid).delete().catch(() => {});
    console.log(`✗ Reverted ${email} to athlete and deleted trainerPublicProfiles doc.`);
    return;
  }

  // Defaults para trainer fields — sobreescribibles luego desde la app.
  const trainerBio = data.trainerBio ?? 'Personal trainer en TREINO.';
  const trainerSpecialty = data.trainerSpecialty ?? 'hipertrofia';
  const trainerMonthlyRate = data.trainerMonthlyRate ?? 8000;

  await userRef.update({
    role: 'trainer',
    trainerBio,
    trainerSpecialty,
    trainerMonthlyRate,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Dual-write a trainerPublicProfiles (lo que normalmente hace UserRepository.update).
  await db.collection('trainerPublicProfiles').doc(uid).set(
    {
      uid,
      displayName: data.displayName,
      displayNameLowercase: (data.displayName || '').trim().toLowerCase(),
      avatarUrl: data.avatarUrl ?? null,
      trainerBio,
      trainerSpecialty,
      trainerMonthlyRate,
    },
    { merge: true },
  );

  // Dual-write a userPublicProfiles — generic public identity, leída por
  // ChatScreen y cualquier feature que muestra el nombre de "otro user"
  // sin importar su rol. Sin esto, cuentas creadas directo via Admin SDK
  // (sin pasar por signup) quedan invisibles ahí y caen al fallback
  // "Usuario" en el chat. REQ-UPP-014/015 + bugfix coach-chat smoke 2026-05-22.
  await db.collection('userPublicProfiles').doc(uid).set(
    {
      uid,
      displayName: data.displayName,
      displayNameLowercase: (data.displayName || '').trim().toLowerCase(),
      avatarUrl: data.avatarUrl ?? null,
      gymId: data.gymId ?? null,
    },
    { merge: true },
  );

  console.log(`✓ Promoted ${email} to trainer.`);
  console.log(`  uid: ${uid}`);
  console.log(`  trainerSpecialty: ${trainerSpecialty}`);
  console.log(`  trainerMonthlyRate: \$${trainerMonthlyRate}/mes`);
  console.log(`  userPublicProfiles backfilled (displayName: ${data.displayName ?? '(no name)'})`);
  console.log('');
  console.log('Logout + login again on the app to see the TrainerCoachView.');
}

promote()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('FAILED:', err.message);
    process.exit(1);
  });
