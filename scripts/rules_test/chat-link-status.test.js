'use strict';

/**
 * Firestore Security Rules test suite — chatRelationshipOk link status
 * (QA audit 2026-07-30, finding H8).
 *
 * Creating a trainer↔athlete chat requires a `trainer_links` doc whose status
 * makes the relationship "current". Before this change the rule required
 * `status == 'active'`, so messaging a PAUSED athlete (no prior chat) failed
 * with permission-denied in a loop. Product decision (2026-07-31): pausing is
 * a temporary hold, not a cut — the chat must keep working. So the rule now
 * accepts `status in ['active', 'paused']`, and 'terminated' stays denied.
 *
 * Run via: JAVA_HOME=/opt/homebrew/opt/openjdk@21 bash scripts/test_rules.sh
 */

const { initializeTestEnvironment, assertFails, assertSucceeds } =
  require('@firebase/rules-unit-testing');
const { readFileSync } = require('fs');
const path = require('path');

const PROJECT_ID = 'treino-test-rules';
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');

// 'athlete' < 'coach' alphabetically → deterministic sorted members + chatId.
const COACH = 'coach';
const ATHLETE = 'athlete';
const CHAT_ID = 'athlete_coach';
const LINK_ID = 'link-1';

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(RULES_PATH, 'utf8'),
      host: 'localhost',
      port: 8080,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

async function seedLink(status) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('trainer_links').doc(LINK_ID).set({
      trainerId: COACH,
      athleteId: ATHLETE,
      status,
    });
  });
}

function createChatAs(uid) {
  return testEnv
    .authenticatedContext(uid)
    .firestore()
    .collection('chats')
    .doc(CHAT_ID)
    .set({
      members: [ATHLETE, COACH],
      linkId: LINK_ID,
      createdAt: new Date(),
    });
}

test('active link → the trainer CAN create the chat (regression)', async () => {
  await seedLink('active');
  await assertSucceeds(createChatAs(COACH));
});

test('paused link → the trainer CAN create the chat (H8 fix)', async () => {
  await seedLink('paused');
  await assertSucceeds(createChatAs(COACH));
});

test('paused link → the athlete can also create the chat', async () => {
  await seedLink('paused');
  await assertSucceeds(createChatAs(ATHLETE));
});

test('terminated link → chat creation is DENIED (relationship is cut)', async () => {
  await seedLink('terminated');
  await assertFails(createChatAs(COACH));
});

test('pending link → chat creation is DENIED (not accepted yet)', async () => {
  await seedLink('pending');
  await assertFails(createChatAs(COACH));
});
