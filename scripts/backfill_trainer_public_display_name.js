/**
 * backfill_trainer_public_display_name.js
 *
 * Rellena `displayName` y `displayNameLowercase` en las tarjetas de
 * `trainerPublicProfiles/{uid}` que quedaron sin nombre (el directorio
 * "Encontrá tu coach" las mostraba con "?", y `listAll()` las excluía por el
 * `orderBy('displayNameLowercase')`). El nombre sale de `users/{uid}.displayName`.
 *
 * Causa: la tarjeta se creaba desde "Editar perfil de PF" sin nombre. Ya está
 * corregido en `UserRepository.update`; este script arregla las que ya existen.
 *
 * ────────────────────────────────────────────────────────────────────────────
 * USO (desde la raíz del proyecto)
 * ────────────────────────────────────────────────────────────────────────────
 *   export TREINO_SA_KEY="~/.config/treino/sa-key.json"   # ver scripts/README.md (#834)
 *
 *   # DRY-RUN (default): sólo lista qué escribiría, no toca nada.
 *   node scripts/backfill_trainer_public_display_name.js
 *
 *   # Escribe de verdad:
 *   node scripts/backfill_trainer_public_display_name.js --apply
 *
 *   # Contra el emulador no hace falta clave:
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 \
 *     node scripts/backfill_trainer_public_display_name.js
 *
 * ────────────────────────────────────────────────────────────────────────────
 * SEGURIDAD
 * ────────────────────────────────────────────────────────────────────────────
 * - Sólo toca tarjetas con `displayName` vacío/ausente Y con nombre no vacío
 *   en `users/{uid}`. Nunca pisa un nombre existente.
 * - merge:true y sólo esas dos claves. Idempotente.
 * - No crea tarjetas: recorre las que ya existen.
 * ────────────────────────────────────────────────────────────────────────────
 */

'use strict';

const { inicializarAdmin } = require('./lib/admin');
const { getFirestore } = require('firebase-admin/firestore');

const { app } = inicializarAdmin();
const db = getFirestore(app);

const apply = process.argv.includes('--apply');

async function main() {
  console.log(apply ? 'MODO APPLY: escribe.' : 'DRY-RUN: no escribe (usá --apply).');

  const tarjetas = await db.collection('trainerPublicProfiles').get();
  let candidatas = 0;
  let sinNombreEnUsers = 0;
  let escritas = 0;

  for (const tarjeta of tarjetas.docs) {
    const nombreActual = tarjeta.get('displayName');
    if (typeof nombreActual === 'string' && nombreActual.trim() !== '') continue;

    const user = await db.collection('users').doc(tarjeta.id).get();
    const nombre = user.exists ? user.get('displayName') : null;
    if (typeof nombre !== 'string' || nombre.trim() === '') {
      sinNombreEnUsers++;
      console.log(`  ${tarjeta.id}: sin nombre tampoco en users/, se omite`);
      continue;
    }

    candidatas++;
    const limpio = nombre.trim();
    console.log(`  ${tarjeta.id}: -> "${limpio}"`);
    if (apply) {
      await tarjeta.ref.set(
        { displayName: limpio, displayNameLowercase: limpio.toLowerCase() },
        { merge: true },
      );
      escritas++;
    }
  }

  console.log(
    `Tarjetas: ${tarjetas.size}. A rellenar: ${candidatas}. ` +
      `Sin nombre en users/: ${sinNombreEnUsers}. Escritas: ${escritas}.`,
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
