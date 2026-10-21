'use strict';

/**
 * Firestore Security Rules — archivar y eliminar un chat, POR MIEMBRO.
 *
 * Cada miembro estampa SU entrada en `archivedAt.{uid}` (archivar) o
 * `hiddenBefore.{uid}` (eliminar: oculta el historial previo sólo para él).
 * Nadie toca la entrada del otro, el valor va pineado a `request.time`, y el
 * lado que perdió la escritura (unfollow) igual puede sacarse el chat de la
 * bandeja. Ver `ownStampOk` en `match /chats/{chatId}`.
 *
 * Run via: bash scripts/test_rules.sh
 */

const { initializeTestEnvironment, assertFails, assertSucceeds } =
  require('@firebase/rules-unit-testing');
const firebase = require('firebase/compat/app');
require('firebase/compat/firestore');
const { readFileSync } = require('fs');
const path = require('path');

const PROJECT_ID = 'treino-test-rules';
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');

// `emulators:exec` exporta FIRESTORE_EMULATOR_HOST; sin él, el 8080 de siempre.
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || 'localhost:8080')
  .split(':');

const ALICE = 'alice';
const BOB = 'bob';
const EVE = 'eve';
const CHAT_ID = 'alice_bob';

const { serverTimestamp, delete: deleteField } = firebase.firestore.FieldValue;
const Timestamp = firebase.firestore.Timestamp;

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(RULES_PATH, 'utf8'),
      host: HOST,
      port: Number(PORT),
    },
  });
  // Cargar firestore.rules entero en un emulador frío pasa los 5 s por
  // defecto de jest, y el hook caído tumba la suite como si fueran 15 rojos.
}, 30000);

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

/** Chat social alice↔bob. Con [bobFollowsAlice], alice puede escribir. */
async function seed({ bobFollowsAlice = true, extra = {} } = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    if (bobFollowsAlice) {
      await db.collection('follows').doc(`${BOB}_${ALICE}`).set({
        id: `${BOB}_${ALICE}`,
        followerUid: BOB,
        followeeUid: ALICE,
        status: 'accepted',
        members: [BOB, ALICE],
        createdAt: new Date(),
      });
    }
    await db.collection('chats').doc(CHAT_ID).set({
      chatId: CHAT_ID,
      members: [ALICE, BOB],
      createdAt: new Date('2026-10-01T00:00:00Z'),
      lastMessageAt: new Date('2026-10-02T00:00:00Z'),
      lastMessageText: 'hola',
      lastMessageSenderId: BOB,
      ...extra,
    });
  });
}

function chatAs(uid) {
  return testEnv.authenticatedContext(uid).firestore()
    .collection('chats').doc(CHAT_ID);
}

describe('archivar (archivedAt.{uid})', () => {
  test('un miembro archiva SU entrada', async () => {
    await seed();
    await assertSucceeds(
      chatAs(ALICE).update({ [`archivedAt.${ALICE}`]: serverTimestamp() }));
  });

  test('sin permiso de escritura (dejaron de seguirlo) igual archiva',
    async () => {
      await seed({ bobFollowsAlice: false });
      await assertSucceeds(
        chatAs(ALICE).update({ [`archivedAt.${ALICE}`]: serverTimestamp() }));
    });

  test('desarchivar es borrar su propia clave', async () => {
    await seed({ extra: { archivedAt: { [ALICE]: new Date('2026-10-03') } } });
    await assertSucceeds(
      chatAs(ALICE).update({ [`archivedAt.${ALICE}`]: deleteField() }));
  });

  test('NO puede archivarle el chat al otro', async () => {
    await seed();
    await assertFails(
      chatAs(ALICE).update({ [`archivedAt.${BOB}`]: serverTimestamp() }));
  });

  test('NO puede desarchivarle el chat al otro', async () => {
    await seed({ extra: { archivedAt: { [BOB]: new Date('2026-10-03') } } });
    await assertFails(
      chatAs(ALICE).update({ [`archivedAt.${BOB}`]: deleteField() }));
  });

  test('NO acepta una fecha del cliente (va pineado a request.time)',
    async () => {
      await seed();
      await assertFails(chatAs(ALICE).update({
        [`archivedAt.${ALICE}`]: Timestamp.fromDate(new Date('2030-01-01')),
      }));
    });

  test('un no-miembro no archiva nada', async () => {
    await seed();
    await assertFails(
      chatAs(EVE).update({ [`archivedAt.${EVE}`]: serverTimestamp() }));
  });
});

describe('eliminar (hiddenBefore.{uid})', () => {
  test('un miembro elimina el chat para él', async () => {
    await seed();
    await assertSucceeds(
      chatAs(BOB).update({ [`hiddenBefore.${BOB}`]: serverTimestamp() }));
  });

  test('sin permiso de escritura igual lo elimina para él', async () => {
    await seed({ bobFollowsAlice: false });
    await assertSucceeds(
      chatAs(ALICE).update({ [`hiddenBefore.${ALICE}`]: serverTimestamp() }));
  });

  test('NO puede eliminárselo al otro', async () => {
    await seed();
    await assertFails(
      chatAs(ALICE).update({ [`hiddenBefore.${BOB}`]: serverTimestamp() }));
  });

  test('NO puede des-eliminar (borrar su clave)', async () => {
    await seed({ extra: { hiddenBefore: { [ALICE]: new Date('2026-10-03') } } });
    await assertFails(
      chatAs(ALICE).update({ [`hiddenBefore.${ALICE}`]: deleteField() }));
  });

  test('NO acepta una fecha del cliente', async () => {
    await seed();
    await assertFails(chatAs(ALICE).update({
      [`hiddenBefore.${ALICE}`]: Timestamp.fromDate(new Date('2020-01-01')),
    }));
  });

  test('el doc del chat sigue sin poder borrarse', async () => {
    await seed();
    await assertFails(chatAs(ALICE).delete());
  });
});

describe('no abre un costado', () => {
  test('el lado sin escritura no cuela un preview junto con el archivado',
    async () => {
      await seed({ bobFollowsAlice: false });
      await assertFails(chatAs(ALICE).update({
        [`archivedAt.${ALICE}`]: serverTimestamp(),
        lastMessageText: 'spam',
      }));
    });

  test('mandar un mensaje sigue funcionando con estampas viejas en el doc',
    async () => {
      await seed({
        extra: {
          archivedAt: { [ALICE]: new Date('2026-10-03') },
          hiddenBefore: { [BOB]: new Date('2026-10-03') },
        },
      });
      await assertSucceeds(chatAs(ALICE).update({
        lastMessageAt: serverTimestamp(),
        lastMessageText: 'volví',
        lastMessageSenderId: ALICE,
      }));
    });
});
