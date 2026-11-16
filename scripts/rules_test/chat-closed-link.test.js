'use strict';

/**
 * Firestore Security Rules — chat CERRADO por fin de vínculo (#1697).
 *
 * Decisión de producto: cuando el vínculo PF↔alumno termina, el chat del par se
 * cierra. Nadie manda mensajes nuevos, el historial sigue legible, y volver a
 * vincularse lo reabre. El estado vive en `chats/{id}.closedAt`, que escribe
 * SÓLO una Cloud Function (Admin SDK: no pasa por las reglas, acá se simula con
 * `withSecurityRulesDisabled`). Sin el campo el chat está abierto, así los docs
 * y los builds anteriores no cambian.
 *
 * Las reglas tocadas: `senderMayPost` (messages/create), `chatWriterOk` (el
 * preview de `chats/update`) y el pin de `closedAt` en `chats/update` + create.
 * `lastRead`, archivar y eliminar siguen permitidos en un chat cerrado.
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

// 'athlete' < 'coach' → members y chatId ordenados.
const COACH = 'coach';
const ATHLETE = 'athlete';
const EVE = 'eve';
const CHAT_ID = 'athlete_coach';
const LINK_ID = 'link-1';

const { serverTimestamp, delete: deleteField } = firebase.firestore.FieldValue;

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
}, 30000);

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

/**
 * Chat de Coach athlete↔coach con un mensaje previo, el vínculo ya terminado.
 * [closedAt]: `true` lo cierra, `false` lo deja sin el campo (abierto), o el
 * valor literal a sembrar (ej. `null`). [blocked]: el coach bloqueó al alumno.
 */
async function seed({ closedAt = true, blocked = false } = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection('trainer_links').doc(LINK_ID).set({
      trainerId: COACH, athleteId: ATHLETE, status: 'terminated',
    });
    if (blocked) {
      await db.collection('blocks').doc(`${COACH}_${ATHLETE}`).set({
        id: `${COACH}_${ATHLETE}`, blockerUid: COACH, blockedUid: ATHLETE,
        members: [COACH, ATHLETE], createdAt: new Date(),
      });
    }
    const chat = {
      chatId: CHAT_ID,
      members: [ATHLETE, COACH],
      linkId: LINK_ID,
      createdAt: new Date('2026-10-01T00:00:00Z'),
      lastMessageAt: new Date('2026-10-02T00:00:00Z'),
      lastMessageText: 'hola',
      lastMessageSenderId: COACH,
    };
    if (closedAt === true) chat.closedAt = new Date('2026-10-20T12:00:00Z');
    else if (closedAt !== false) chat.closedAt = closedAt;
    await db.collection('chats').doc(CHAT_ID).set(chat);
    await db.collection('chats').doc(CHAT_ID).collection('messages')
      .doc('previo').set({
        senderId: COACH, text: 'hola', createdAt: new Date('2026-10-02T00:00:00Z'),
      });
  });
}

/** Simula a la Cloud Function (Admin SDK): reabre el chat al revincular. */
async function reopenAsAdmin() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('chats').doc(CHAT_ID)
      .update({ closedAt: deleteField() });
  });
}

const db = (uid) => testEnv.authenticatedContext(uid).firestore();
const chatAs = (uid) => db(uid).collection('chats').doc(CHAT_ID);
const sendText = (uid, id = 'm1') => chatAs(uid).collection('messages').doc(id)
  .set({ senderId: uid, text: 'hola', createdAt: serverTimestamp() });
const sendMedia = (uid, id = 'm2') => chatAs(uid).collection('messages').doc(id)
  .set({
    senderId: uid, mediaUrl: 'https://x/y.jpg', mediaType: 'image',
    createdAt: serverTimestamp(),
  });
const previewAs = (uid) => chatAs(uid).update({
  lastMessageAt: serverTimestamp(),
  lastMessageText: 'hola',
  lastMessageSenderId: uid,
});
/** El envío real de la app: mensaje + preview en UN batch. */
function sendBatchAs(uid, id = 'm3') {
  // UNA sola instancia de Firestore: el batch rechaza refs de otra.
  const d = db(uid);
  const chat = d.collection('chats').doc(CHAT_ID);
  const batch = d.batch();
  batch.set(chat.collection('messages').doc(id),
    { senderId: uid, text: 'hola', createdAt: serverTimestamp() });
  batch.update(chat, {
    lastMessageAt: serverTimestamp(),
    lastMessageText: 'hola',
    lastMessageSenderId: uid,
  });
  return batch.commit();
}

describe('chat CERRADO (closedAt presente): nadie escribe', () => {
  test.each([['el ex-PF', COACH], ['el ex-alumno', ATHLETE]])(
    'mensaje de texto DENEGADO a %s', async (_n, uid) => {
      await seed();
      await assertFails(sendText(uid));
    });

  test.each([['el ex-PF', COACH], ['el ex-alumno', ATHLETE]])(
    'mensaje con media DENEGADO a %s', async (_n, uid) => {
      await seed();
      await assertFails(sendMedia(uid));
    });

  test.each([['el ex-PF', COACH], ['el ex-alumno', ATHLETE]])(
    'preview (lastMessage*) DENEGADO a %s', async (_n, uid) => {
      await seed();
      await assertFails(previewAs(uid));
    });

  test.each([['el ex-PF', COACH], ['el ex-alumno', ATHLETE]])(
    'el batch de envío completo (mensaje + preview) falla para %s',
    async (_n, uid) => {
      await seed();
      await assertFails(sendBatchAs(uid));
    });

  test('un campo cualquiera que no es de la allowlist tampoco se cuela',
    async () => {
      await seed();
      await assertFails(chatAs(COACH).update({ lastMessageText: 'spam' }));
    });
});

describe('closedAt es de la Cloud Function: ningún miembro lo toca', () => {
  test.each([['el ex-PF', COACH], ['el ex-alumno', ATHLETE]])(
    '%s NO puede ponerlo en un chat abierto', async (_n, uid) => {
      await seed({ closedAt: false });
      await assertFails(chatAs(uid).update({ closedAt: serverTimestamp() }));
    });

  test.each([['el ex-PF', COACH], ['el ex-alumno', ATHLETE]])(
    '%s NO puede cambiarlo', async (_n, uid) => {
      await seed();
      await assertFails(
        chatAs(uid).update({ closedAt: new Date('2030-01-01T00:00:00Z') }));
    });

  test.each([['el ex-PF', COACH], ['el ex-alumno', ATHLETE]])(
    '%s NO puede borrarlo para reabrir el chat', async (_n, uid) => {
      await seed();
      await assertFails(chatAs(uid).update({ closedAt: deleteField() }));
      // Y el chat sigue cerrado.
      await assertFails(sendText(uid));
    });

  test('NO puede ponérselo al otro junto con un lastRead legítimo',
    async () => {
      await seed({ closedAt: false });
      await assertFails(chatAs(ATHLETE).update({
        [`lastRead.${ATHLETE}`]: serverTimestamp(),
        closedAt: serverTimestamp(),
      }));
    });

  test('un no-miembro tampoco', async () => {
    await seed({ closedAt: false });
    await assertFails(chatAs(EVE).update({ closedAt: serverTimestamp() }));
  });

  describe('create', () => {
    const create = (uid, extra = {}) => chatAs(uid).set({
      members: [ATHLETE, COACH],
      linkId: LINK_ID,
      createdAt: new Date(),
      ...extra,
    });
    const seedActiveLink = () => testEnv.withSecurityRulesDisabled(
      (ctx) => ctx.firestore().collection('trainer_links').doc(LINK_ID)
        .set({ trainerId: COACH, athleteId: ATHLETE, status: 'active' }));

    test('control: el mismo create SIN closedAt pasa', async () => {
      await seedActiveLink();
      await assertSucceeds(create(COACH));
    });

    test('un chat NO nace cerrado desde el cliente', async () => {
      await seedActiveLink();
      await assertFails(create(COACH, { closedAt: new Date() }));
    });

    test('un `closedAt: null` explícito en el payload se tolera (= abierto)',
      async () => {
        await seedActiveLink();
        await assertSucceeds(create(COACH, { closedAt: null }));
      });
  });
});

describe('lo que SIGUE permitido en un chat cerrado', () => {
  test.each([['el ex-PF', COACH], ['el ex-alumno', ATHLETE]])(
    '%s lee el chat y todo el historial', async (_n, uid) => {
      await seed();
      await assertSucceeds(chatAs(uid).get());
      await assertSucceeds(chatAs(uid).collection('messages').get());
      await assertSucceeds(
        chatAs(uid).collection('messages').doc('previo').get());
    });

  test('la lista de chats del usuario (array-contains) sigue andando',
    async () => {
      await seed();
      await assertSucceeds(db(ATHLETE).collection('chats')
        .where('members', 'array-contains', ATHLETE).get());
    });

  test.each([['el ex-PF', COACH], ['el ex-alumno', ATHLETE]])(
    '%s marca como leído (lastRead propio)', async (_n, uid) => {
      await seed();
      await assertSucceeds(
        chatAs(uid).update({ [`lastRead.${uid}`]: serverTimestamp() }));
    });

  test.each([['el ex-PF', COACH], ['el ex-alumno', ATHLETE]])(
    '%s archiva el chat (archivedAt propio)', async (_n, uid) => {
      await seed();
      await assertSucceeds(
        chatAs(uid).update({ [`archivedAt.${uid}`]: serverTimestamp() }));
    });

  test.each([['el ex-PF', COACH], ['el ex-alumno', ATHLETE]])(
    '%s elimina el chat de SU bandeja (hiddenBefore propio)', async (_n, uid) => {
      await seed();
      await assertSucceeds(
        chatAs(uid).update({ [`hiddenBefore.${uid}`]: serverTimestamp() }));
    });

  test('un no-miembro sigue sin leer', async () => {
    await seed();
    await assertFails(chatAs(EVE).get());
  });

  test('el doc sigue sin poder borrarse', async () => {
    await seed();
    await assertFails(chatAs(COACH).delete());
  });

  test('revincular (la CF borra closedAt) reabre el chat para los dos',
    async () => {
      await seed();
      await assertFails(sendText(COACH, 'antes'));
      await reopenAsAdmin();
      await assertSucceeds(sendText(COACH, 'despues-coach'));
      await assertSucceeds(sendBatchAs(ATHLETE, 'despues-alumno'));
    });
});

describe('chat SIN closedAt: lo de antes sigue andando (regresión)', () => {
  test.each([['el PF', COACH], ['el alumno', ATHLETE]])(
    '%s manda texto y media', async (_n, uid) => {
      await seed({ closedAt: false });
      await assertSucceeds(sendText(uid));
      await assertSucceeds(sendMedia(uid));
    });

  test.each([['el PF', COACH], ['el alumno', ATHLETE]])(
    '%s escribe el preview', async (_n, uid) => {
      await seed({ closedAt: false });
      await assertSucceeds(previewAs(uid));
    });

  test.each([['el PF', COACH], ['el alumno', ATHLETE]])(
    'el batch de envío completo pasa para %s', async (_n, uid) => {
      await seed({ closedAt: false });
      await assertSucceeds(sendBatchAs(uid));
    });

  test('un `closedAt: null` guardado cuenta como abierto', async () => {
    await seed({ closedAt: null });
    await assertSucceeds(sendBatchAs(ATHLETE));
  });

  test('el update de un chat que tiene closedAt:null no se rompe por el pin',
    async () => {
      await seed({ closedAt: null });
      await assertSucceeds(
        chatAs(COACH).update({ [`lastRead.${COACH}`]: serverTimestamp() }));
    });

  test('el bloqueo sigue cortando el mensaje y el preview', async () => {
    await seed({ closedAt: false, blocked: true });
    await assertFails(sendText(ATHLETE));
    await assertFails(previewAs(ATHLETE));
  });
});
