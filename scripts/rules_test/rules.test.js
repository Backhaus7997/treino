'use strict';

/**
 * Firestore Security Rules test suite — posts + friendships
 * Covers SCENARIO-130, SCENARIO-131, SCENARIO-132
 *
 * Run via: bash scripts/test_rules.sh
 * (Requires Firebase emulator running with firestore enabled)
 */

const { initializeTestEnvironment, assertFails, assertSucceeds } =
  require('@firebase/rules-unit-testing');
const { readFileSync } = require('fs');
const path = require('path');

const PROJECT_ID = 'treino-test-rules';
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');

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

// ---------------------------------------------------------------------------
// SCENARIO-130: non-owner post create is blocked (REQ-PFM-009)
// ---------------------------------------------------------------------------
test('SCENARIO-130: non-owner cannot create a post with a different authorUid', async () => {
  const u2 = testEnv.authenticatedContext('u2');
  await assertFails(
    u2.firestore().collection('posts').doc('p1').set({
      authorUid: 'u1', // u2 is trying to impersonate u1
      text: 'Fake post',
      privacy: 'public',
      createdAt: new Date(),
    }),
  );
});

// Owner can create their own post — sanity check
test('SCENARIO-130 inverse: owner can create a post with matching authorUid', async () => {
  const u1 = testEnv.authenticatedContext('u1');
  await assertSucceeds(
    u1.firestore().collection('posts').doc('p1').set({
      authorUid: 'u1',
      text: 'My post',
      privacy: 'public',
      createdAt: new Date(),
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-131: non-member cannot read a friendship (REQ-PFM-010)
// ---------------------------------------------------------------------------
test('SCENARIO-131: non-member is blocked from reading a friendship doc', async () => {
  // Seed friendship as admin (bypasses rules)
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection('friendships')
      .doc('u1_u2')
      .set({
        members: ['u1', 'u2'],
        requesterId: 'u1',
        status: 'pending',
        createdAt: new Date(),
      });
  });

  const u3 = testEnv.authenticatedContext('u3');
  await assertFails(
    u3.firestore().collection('friendships').doc('u1_u2').get(),
  );
});

// Member can read their own friendship
test('SCENARIO-131 inverse: member can read their friendship doc', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection('friendships')
      .doc('u1_u2')
      .set({
        members: ['u1', 'u2'],
        requesterId: 'u1',
        status: 'pending',
        createdAt: new Date(),
      });
  });

  const u1 = testEnv.authenticatedContext('u1');
  await assertSucceeds(
    u1.firestore().collection('friendships').doc('u1_u2').get(),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-132: requester cannot self-accept (REQ-PFM-010)
// ---------------------------------------------------------------------------
test('SCENARIO-132: requester is blocked from updating status to accepted', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection('friendships')
      .doc('u1_u2')
      .set({
        members: ['u1', 'u2'],
        requesterId: 'u1',
        status: 'pending',
        createdAt: new Date(),
      });
  });

  const u1 = testEnv.authenticatedContext('u1');
  await assertFails(
    u1.firestore().collection('friendships').doc('u1_u2').update({
      status: 'accepted',
    }),
  );
});

// Non-requester member can accept
test('SCENARIO-132 inverse: non-requester member can accept the friendship', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection('friendships')
      .doc('u1_u2')
      .set({
        members: ['u1', 'u2'],
        requesterId: 'u1',
        status: 'pending',
        createdAt: new Date(),
      });
  });

  const u2 = testEnv.authenticatedContext('u2');
  await assertSucceeds(
    u2.firestore().collection('friendships').doc('u1_u2').update({
      requesterId: 'u1',
      members: ['u1', 'u2'],
      status: 'accepted',
    }),
  );
});
