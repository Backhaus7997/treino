'use strict';

/**
 * Storage Security Rules test suite — chatMedia membership gate
 * (rules-hardening Slice A / AD-2, REQ:gym-chat-media)
 *
 * Closes the private chat-media exfiltration vector: chatId is
 * deterministic (ChatRepository.chatIdFor = sorted([a,b]).join('_')) and
 * uids are enumerable (userPublicProfiles is world-readable), so any
 * authenticated non-member could `get`/`list` another pair's chat media
 * under the old `allow read: if request.auth != null` rule.
 *
 * Run via: bash scripts/test_rules.sh
 * (Requires the Firebase emulator running with firestore AND storage enabled)
 */

const { initializeTestEnvironment, assertFails, assertSucceeds } =
  require('@firebase/rules-unit-testing');
const { readFileSync } = require('fs');
const path = require('path');

// NOTE: this MUST match the emulator's configured default project
// (`.firebaserc` -> "treino-dev") rather than an arbitrary test project id.
// firebase.json sets `emulators.singleProjectMode: true`, which pins the
// Storage rules' cross-service `firestore.get()` calls to the suite's
// default project regardless of what projectId this test process requests —
// using a different id here causes `firestore.get()` to look up the seeded
// chat doc under the WRONG project and fail with a null-value evaluation
// error (confirmed against a live emulator; see apply-progress notes).
const PROJECT_ID = 'treino-dev';
const FIRESTORE_RULES_PATH = path.resolve(__dirname, '../../firestore.rules');
const STORAGE_RULES_PATH = path.resolve(__dirname, '../../storage.rules');

const CHAT_ID = 'uidA_uidB';
const MEMBER_A = 'uidA';
const MEMBER_B = 'uidB';
const ATTACKER = 'attacker';
const MEDIA_PATH = `chatMedia/${CHAT_ID}/${MEMBER_A}/photo.jpg`;

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(FIRESTORE_RULES_PATH, 'utf8'),
      host: 'localhost',
      port: 8080,
    },
    storage: {
      rules: readFileSync(STORAGE_RULES_PATH, 'utf8'),
      host: 'localhost',
      port: 9199,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
});

/**
 * Seeds the gating `chats/{chatId}` doc (bypassing rules, as the real
 * write path does via ChatRepository.getOrCreate) and a fake media object
 * under chatMedia/{chatId}/{memberA}/photo.jpg (also bypassing rules — we
 * are testing READ access, not write).
 */
async function seedChatAndMedia() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('chats').doc(CHAT_ID).set({
      chatId: CHAT_ID,
      members: [MEMBER_A, MEMBER_B],
      createdAt: new Date(),
    });
    await ctx
      .storage()
      .ref(MEDIA_PATH)
      .put(Buffer.from('fake-image-bytes'), { contentType: 'image/jpeg' });
  });
}

// ---------------------------------------------------------------------------
// REQ:gym-chat-media#Get Requires Chat Membership — non-member scenario
// ---------------------------------------------------------------------------
test('SCENARIO-CHATMEDIA-01: non-member cannot getMetadata on another pair chat media', async () => {
  await seedChatAndMedia();

  const attacker = testEnv.authenticatedContext(ATTACKER);
  await assertFails(attacker.storage().ref(MEDIA_PATH).getMetadata());
});

test('SCENARIO-CHATMEDIA-01b: non-member cannot getDownloadURL on another pair chat media', async () => {
  await seedChatAndMedia();

  const attacker = testEnv.authenticatedContext(ATTACKER);
  await assertFails(attacker.storage().ref(MEDIA_PATH).getDownloadURL());
});

// ---------------------------------------------------------------------------
// REQ:gym-chat-media#Get Requires Chat Membership — unauthenticated
// (already correct today: request.auth != null already denies this; kept
// as a non-regression guard, not a new RED.)
// ---------------------------------------------------------------------------
test('SCENARIO-CHATMEDIA-02: unauthenticated caller cannot get chat media (non-regression)', async () => {
  await seedChatAndMedia();

  const unauthed = testEnv.unauthenticatedContext();
  await assertFails(unauthed.storage().ref(MEDIA_PATH).getMetadata());
});

// ---------------------------------------------------------------------------
// REQ:gym-chat-media#chatMedia List Denial — both scenarios
// list is unconditionally closed, even for members.
// ---------------------------------------------------------------------------
test('SCENARIO-CHATMEDIA-03: non-member cannot list a chat media folder', async () => {
  await seedChatAndMedia();

  const attacker = testEnv.authenticatedContext(ATTACKER);
  await assertFails(
    attacker.storage().ref(`chatMedia/${CHAT_ID}`).listAll(),
  );
});

test('SCENARIO-CHATMEDIA-04: a chat member cannot list their own chat media folder either', async () => {
  await seedChatAndMedia();

  const member = testEnv.authenticatedContext(MEMBER_A);
  await assertFails(
    member.storage().ref(`chatMedia/${CHAT_ID}`).listAll(),
  );
});

// ---------------------------------------------------------------------------
// REQ:gym-chat-media#Get Requires Chat Membership — member scenario
// Legit-path anchor: must stay green through the GREEN step.
// ---------------------------------------------------------------------------
test('SCENARIO-CHATMEDIA-05: a chat member can getMetadata on their own chat media', async () => {
  await seedChatAndMedia();

  const member = testEnv.authenticatedContext(MEMBER_B);
  await assertSucceeds(member.storage().ref(MEDIA_PATH).getMetadata());
});

test('SCENARIO-CHATMEDIA-05b: a chat member can getDownloadURL on their own chat media', async () => {
  await seedChatAndMedia();

  const member = testEnv.authenticatedContext(MEMBER_B);
  await assertSucceeds(member.storage().ref(MEDIA_PATH).getDownloadURL());
});

// ---------------------------------------------------------------------------
// REQ:gym-chat-media#Write/Delete Unaffected
// Pure regression guard proving Slice A does not touch write/delete.
// ---------------------------------------------------------------------------
test('SCENARIO-CHATMEDIA-06: the owning uploader can write their own chat media', async () => {
  const uploader = testEnv.authenticatedContext(MEMBER_A);
  await assertSucceeds(
    uploader
      .storage()
      .ref(`chatMedia/${CHAT_ID}/${MEMBER_A}/new-photo.jpg`)
      .put(Buffer.from('fake-image-bytes'), { contentType: 'image/jpeg' }),
  );
});

test('SCENARIO-CHATMEDIA-07: the owning uploader can delete their own chat media', async () => {
  await seedChatAndMedia();

  const uploader = testEnv.authenticatedContext(MEMBER_A);
  await assertSucceeds(uploader.storage().ref(MEDIA_PATH).delete());
});
