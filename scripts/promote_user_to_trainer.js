'use strict';

/**
 * promote_user_to_trainer.js
 *
 * Flips `users/{uid}.role` to `'trainer'` AND backfills the public identity
 * fields (`displayName` / `displayNameLowercase`) into `trainerPublicProfiles`.
 *
 * Why the backfill: the in-app trainer-edit onboarding form only submits
 * trainer-specific fields (`trainerBio`, `trainerSpecialty`, ...), never the
 * displayName (that was chosen during athlete profile-setup, BEFORE any
 * trainerPublicProfiles doc existed). Without this, a promoted user lands in
 * discovery with a BLANK name. We copy it from the `users` doc using
 * SetOptions(merge:true) — same semantics as UserRepository's dual-write — so
 * it coexists with the trainer fields written later at onboarding.
 *
 * Trainer profile fields are still NOT seeded — the user must complete the
 * in-app onboarding flow to populate them.
 *
 * See scripts/README.md for full usage and prerequisites.
 *
 * ADR-TPO-007: role-flip + name backfill, uid-based, validate doc exists, idempotent.
 *
 * 🚨 ESCRIBE EN PRODUCCIÓN por Admin SDK —salteándose la regla de rol
 * inmutable— salvo que apuntes al emulador. Es el entrypoint de
 * `npm run promote:trainer`, que no nombra el proyecto en ningún lado.
 * Imprime un cartel antes del primer write cuando el destino es producción. (#826)
 */

// El cartel va ANTES de inicializar: lo que frena a alguien tiene que estar en
// pantalla antes del primer write, no después. `npm run promote:trainer` no
// nombra el proyecto en ningún lado — lo resuelve el SDK desde el entorno. (#826)
const { bannerDeProduccion } = require('./lib/firebase_projects');
const { contraEmuladorDe, projectIdObjetivo } = require('./lib/target_project');
// #846 — `contraEmuladorDe(['firestore'])`, no el `usandoEmulador()` que hacía
// OR entre Firestore y Auth. Este script escribe SÓLO en Firestore
// (`users/<uid>`, no toca `admin.auth()`), así que un
// `FIREBASE_AUTH_EMULATOR_HOST` heredado de una sesión de `emulator.sh` apagaba
// el cartel mientras el write iba a `treino-dev`. El cartel se calla cuando
// está desviado el servicio que este proceso TOCA, no cualquiera.
const bannerProd = bannerDeProduccion(projectIdObjetivo(), {
  contraEmulador: contraEmuladorDe(['firestore']),
});
if (bannerProd) console.warn(bannerProd);

// Credenciales: la única puerta (#834). Sin `$TREINO_SA_KEY` esto falla cerrado
// con la migración; contra el emulador no pide nada. Ver scripts/lib/admin.js.
const { inicializarAdmin } = require('./lib/admin');

const { admin } = inicializarAdmin();
const db = admin.firestore();

async function run() {
  const uid = process.argv[2];
  if (!uid) {
    console.error('USAGE: node scripts/promote_user_to_trainer.js <uid>');
    process.exit(1);
  }

  const snap = await db.collection('users').doc(uid).get();
  if (!snap.exists) {
    console.error(`User document users/${uid} not found.`);
    process.exit(1);
  }

  const { email, displayName } = snap.data();
  console.log(
    `Promoting ${email} (${displayName || '(no displayName)'}) → role: trainer`,
  );

  const batch = db.batch();
  batch.update(db.collection('users').doc(uid), { role: 'trainer' });

  // Backfill the public name so the trainer is not blank in discovery. merge:true
  // keeps it compatible with the trainer fields the onboarding dual-write adds later.
  if (displayName) {
    batch.set(
      db.collection('trainerPublicProfiles').doc(uid),
      {
        uid,
        displayName,
        displayNameLowercase: displayName.trim().toLowerCase(),
      },
      { merge: true },
    );
    console.log(`Backfilling trainerPublicProfiles name → ${displayName}`);
  } else {
    console.warn(
      'WARNING: user has no displayName — public name NOT backfilled.',
    );
  }

  await batch.commit();
  console.log('Done.');
  process.exit(0);
}

run().catch((err) => {
  console.error('FAILED:', err);
  process.exit(1);
});
