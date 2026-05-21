'use strict';

/**
 * Firestore Security Rules test suite — posts + friendships + userPublicProfiles
 * Covers SCENARIO-130, SCENARIO-131, SCENARIO-132, SCENARIO-268..271
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

// ---------------------------------------------------------------------------
// SCENARIO-268: any authenticated user can read another user's
// userPublicProfile doc (cross-user GET succeeds). REQ-UPP-014.
// ---------------------------------------------------------------------------
test('SCENARIO-268: non-owner can read another user public profile doc', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('userPublicProfiles').doc('u1').set({
      uid: 'u1',
      displayName: 'Martin',
      displayNameLowercase: 'martin',
      avatarUrl: null,
      gymId: 'smart-fit-palermo',
    });
  });

  const u2 = testEnv.authenticatedContext('u2');
  await assertSucceeds(
    u2.firestore().collection('userPublicProfiles').doc('u1').get(),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-269: any authenticated user can run prefix-range list query
// against userPublicProfiles (enables searchByDisplayName). REQ-UPP-014.
// ---------------------------------------------------------------------------
test('SCENARIO-269: non-owner can run prefix-range list query on userPublicProfiles', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const fs = ctx.firestore();
    await fs.collection('userPublicProfiles').doc('u1').set({
      uid: 'u1',
      displayName: 'Martin',
      displayNameLowercase: 'martin',
      avatarUrl: null,
      gymId: null,
    });
    await fs.collection('userPublicProfiles').doc('u2').set({
      uid: 'u2',
      displayName: 'Mateo',
      displayNameLowercase: 'mateo',
      avatarUrl: null,
      gymId: null,
    });
  });

  const u3 = testEnv.authenticatedContext('u3');
  await assertSucceeds(
    u3
      .firestore()
      .collection('userPublicProfiles')
      .where('displayNameLowercase', '>=', 'm')
      .where('displayNameLowercase', '<', 'm')
      .limit(20)
      .get(),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-270: non-owner cannot write to another user's public profile doc.
// REQ-UPP-015.
// ---------------------------------------------------------------------------
test('SCENARIO-270: non-owner is blocked from writing another user public profile', async () => {
  const u2 = testEnv.authenticatedContext('u2');
  await assertFails(
    u2.firestore().collection('userPublicProfiles').doc('u1').set({
      uid: 'u1',
      displayName: 'Hijacked',
      displayNameLowercase: 'hijacked',
      avatarUrl: null,
      gymId: null,
    }),
  );
});

// Owner can write their own public profile — sanity check
test('SCENARIO-270 inverse: owner can write their own public profile', async () => {
  const u1 = testEnv.authenticatedContext('u1');
  await assertSucceeds(
    u1.firestore().collection('userPublicProfiles').doc('u1').set({
      uid: 'u1',
      displayName: 'Martin',
      displayNameLowercase: 'martin',
      avatarUrl: null,
      gymId: null,
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-271: reading a non-existent friendship doc returns empty
// snapshot without permission-denied. Covers the friendships rule fix
// (resource == null branch) discovered during user-public-profiles
// smoke test. Pre-existing rule denied this case, causing
// publicProfileViewProvider to error when viewing profiles with no
// prior friendship interaction.
// ---------------------------------------------------------------------------
test('SCENARIO-271: non-member can get a non-existent friendship doc (returns empty)', async () => {
  // Do NOT seed any friendship — verify .get() returns empty snap, not failure.
  const u3 = testEnv.authenticatedContext('u3');
  const snap = await assertSucceeds(
    u3.firestore().collection('friendships').doc('u1_u2').get(),
  );
  expect(snap.exists).toBe(false);
});

// ---------------------------------------------------------------------------
// SCENARIO-272: owner can write their own check-in doc. REQ-WRC-004.
// ---------------------------------------------------------------------------
test('SCENARIO-272: owner can create their own check-in for today', async () => {
  const u1 = testEnv.authenticatedContext('u1');
  await assertSucceeds(
    u1.firestore()
      .collection('users').doc('u1')
      .collection('checkIns').doc('2026-05-15')
      .set({
        uid: 'u1',
        date: '2026-05-15',
        checkedInAt: new Date(),
        gymId: 'smart-fit-palermo',
        gymName: 'Smart Fit · Palermo',
      }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-273: non-owner is blocked from reading another user's check-in.
// REQ-WRC-004.
// ---------------------------------------------------------------------------
test('SCENARIO-273: non-owner cannot read another user check-in', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore()
      .collection('users').doc('u1')
      .collection('checkIns').doc('2026-05-15')
      .set({ uid: 'u1', date: '2026-05-15', checkedInAt: new Date() });
  });
  const u2 = testEnv.authenticatedContext('u2');
  await assertFails(
    u2.firestore()
      .collection('users').doc('u1')
      .collection('checkIns').doc('2026-05-15').get(),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-274: non-owner is blocked from writing to another user's check-in.
// REQ-WRC-004.
// ---------------------------------------------------------------------------
test('SCENARIO-274: non-owner cannot write another user check-in', async () => {
  const u2 = testEnv.authenticatedContext('u2');
  await assertFails(
    u2.firestore()
      .collection('users').doc('u1')
      .collection('checkIns').doc('2026-05-15')
      .set({ uid: 'u1', date: '2026-05-15', checkedInAt: new Date() }),
  );
});
