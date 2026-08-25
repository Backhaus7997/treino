/**
 * reset_onboarding_cards.js
 *
 * QA helper: clears the `onboardingSeen` map on `users/{uid}` so the first-run
 * module cards (#627) show again on the next launch.
 *
 * The flag lives in Firestore, not on the device — reinstalling the app or
 * wiping the simulator does NOT bring the cards back. This does.
 *
 * Deleting the whole field is the correct reset: an absent map reads as
 * "nothing seen" for every surface (see OnboardingSurface.shouldShow), which is
 * exactly the state a brand-new account is in. No backfill, no migration.
 *
 * The map is keyed by SURFACE, not by module/tab. The keys are the names of
 * `OnboardingSurface` (lib/features/onboarding/domain/onboarding_surface.dart,
 * `wireKey => name`) — it is a data contract, so keep the two in step:
 *
 *   athleteMobile · trainerMobile · trainerWeb
 *
 * An earlier draft of this header advertised module names (`home`, `feed`).
 * Those never matched anything, so the partial reset silently cleared nothing
 * and QA could believe an account had been reset when it had not.
 *
 * USAGE
 *   export GOOGLE_APPLICATION_CREDENTIALS="scripts/treino-dev-service-account.json"
 *   node scripts/reset_onboarding_cards.js <email>
 *
 *   # Reset only some surfaces instead of all of them:
 *   node scripts/reset_onboarding_cards.js <email> athleteMobile trainerWeb
 */

'use strict';

const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

async function run() {
  const [email, ...modules] = process.argv.slice(2);
  if (!email) {
    console.error(
      'USAGE: node scripts/reset_onboarding_cards.js <email> [module...]',
    );
    process.exit(1);
  }

  const user = await admin.auth().getUserByEmail(email);
  const ref = db.collection('users').doc(user.uid);
  const snap = await ref.get();

  if (!snap.exists) {
    console.error(`No users/${user.uid} document for ${email}.`);
    process.exit(1);
  }

  const before = snap.get('onboardingSeen') || {};
  const seenKeys = Object.keys(before);

  if (seenKeys.length === 0) {
    console.log(`${email} (${user.uid}) has no cards marked as seen — nothing to do.`);
    return;
  }

  console.log(`${email} (${user.uid})`);
  console.log(`  seen before: ${JSON.stringify(before)}`);

  if (modules.length === 0) {
    await ref.update({
      onboardingSeen: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.Timestamp.now(),
    });
    console.log(`  cleared ALL ${seenKeys.length} module(s)`);
  } else {
    const unknown = modules.filter((m) => !seenKeys.includes(m));
    if (unknown.length > 0) {
      console.warn(`  (not currently seen, skipping: ${unknown.join(', ')})`);
      console.warn(`  surfaces on this account: ${seenKeys.join(', ') || '(none)'}`);
      console.warn('  expected surface keys: athleteMobile, trainerMobile, trainerWeb');
    }
    // Rewrite the whole map rather than deleting nested keys: it keeps this
    // script's semantics identical to the client's read-modify-write, and side-
    // steps any doubt about nested-field merge behaviour.
    const after = Object.fromEntries(
      Object.entries(before).filter(([k]) => !modules.includes(k)),
    );
    await ref.update({
      onboardingSeen: after,
      updatedAt: admin.firestore.Timestamp.now(),
    });
    console.log(`  seen after:  ${JSON.stringify(after)}`);
  }

  console.log('Done. Relaunch the app to see the cards again.');
}

run()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
