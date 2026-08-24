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

// SUPERSEDED by the `follow-model` migration (a57c6f79, 2026-08-07).
//
// This scenario used to assert the OTHER member could accept a pending
// friendship. `friendships` is now FROZEN — PR2 of the migration flipped
// `create`/`update`/`delete` to `if false` (ADR-FOLLOW-012); only `read`
// survives, for rollback and for old builds that still list friends. The
// accept flow lives in `follows` now.
//
// The assertion is inverted rather than deleted: a member write must stay
// denied, and this file is where SCENARIO-132 is registered. The freeze
// itself is pinned from every angle by
// `functions/src/__tests__/friendships-freeze-rules.test.ts` (runs in CI).
test('SCENARIO-132 inverse: member cannot accept — friendships are frozen', async () => {
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
  await assertFails(
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

// Owner can write their own public profile — sanity check.
//
// The `users/{uid}` seed is NOT optional since c646376e (2026-07-06): the
// create rule pins the public `gymId` against the private one with
// `getAfter(/databases/$(database)/documents/users/$(uid)).data.gymId`.
// With no `users/u1` doc, that dereference is a null-value error and the
// whole rule evaluation fails — the write comes back PERMISSION_DENIED even
// though the caller IS the owner. Seeding the private doc with the same
// `gymId: null` is what the real signup flow does (ProfileSetup writes
// `users/{uid}` before the public mirror), so this restores the scenario's
// intent instead of relaxing anything.
test('SCENARIO-270 inverse: owner can write their own public profile', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('users').doc('u1').set({
      uid: 'u1',
      role: 'athlete',
      gymId: null,
    });
  });

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

// ---------------------------------------------------------------------------
// gyms/{gymId} — google-places client-side create/update (gym-google-places,
// Plan B pivot). resolveGymPlace CF cannot be deployed (org
// code-assurance.com blocks public-invoker Cloud Functions), so an
// authenticated client now writes gyms/{placeId} directly via
// ResolveGymPlaceService. Covers the new athlete-create + same-shape-update
// branches added to the gyms/{gymId} match block; the pre-existing
// trainer-only self-service branch is untouched.
// ---------------------------------------------------------------------------

/** Helper: base valid google-places gym payload. */
const validGooglePlacesGym = (id) => ({
  id,
  name: 'SportClub Belgrano',
  address: 'Cabildo 1789, CABA',
  lat: -34.5598,
  lng: -58.4615,
  geohash: '6d6m7',
  source: 'google-places',
  brandId: null,
  brandName: null,
  branchName: null,
  createdAt: new Date(),
});

test('GYM-PLACES-01: any authenticated user (not just trainers) can create a google-places gym doc', async () => {
  const athleteA = testEnv.authenticatedContext('athlete-a');
  await assertSucceeds(
    athleteA
      .firestore()
      .collection('gyms')
      .doc('ChIJ_place_1')
      .set(validGooglePlacesGym('ChIJ_place_1')),
  );
});

test('GYM-PLACES-02: create is denied when request.resource.data.id does not match the doc id', async () => {
  const athleteA = testEnv.authenticatedContext('athlete-a');
  await assertFails(
    athleteA
      .firestore()
      .collection('gyms')
      .doc('ChIJ_place_2')
      .set(validGooglePlacesGym('ChIJ_some_other_id')),
  );
});

test('GYM-PLACES-03: create is denied when source is spoofed to self-service without createdBy/trainer role', async () => {
  const athleteA = testEnv.authenticatedContext('athlete-a');
  await assertFails(
    athleteA
      .firestore()
      .collection('gyms')
      .doc('ChIJ_place_3')
      .set({ ...validGooglePlacesGym('ChIJ_place_3'), source: 'self-service' }),
  );
});

test('GYM-PLACES-04: unauthenticated create is denied', async () => {
  const anon = testEnv.unauthenticatedContext();
  await assertFails(
    anon
      .firestore()
      .collection('gyms')
      .doc('ChIJ_place_4')
      .set(validGooglePlacesGym('ChIJ_place_4')),
  );
});

test('GYM-PLACES-05: same-shape update on an existing google-places doc is allowed (read-through cache race)', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection('gyms')
      .doc('ChIJ_place_5')
      .set(validGooglePlacesGym('ChIJ_place_5'));
  });

  const athleteB = testEnv.authenticatedContext('athlete-b');
  await assertSucceeds(
    athleteB
      .firestore()
      .collection('gyms')
      .doc('ChIJ_place_5')
      .set(validGooglePlacesGym('ChIJ_place_5'), { merge: true }),
  );
});

test('GYM-PLACES-06: update cannot flip an existing self-service doc to google-places', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('gyms').doc('gym-legacy').set({
      name: 'Legacy Gym',
      lat: 0,
      lng: 0,
      geohash: 'abcde',
      source: 'self-service',
      createdBy: 'trainer-x',
      createdAt: new Date(),
    });
  });

  const athleteA = testEnv.authenticatedContext('athlete-a');
  await assertFails(
    athleteA
      .firestore()
      .collection('gyms')
      .doc('gym-legacy')
      .set(validGooglePlacesGym('gym-legacy'), { merge: true }),
  );
});

test('GYM-PLACES-07: update that CHANGES the name of an existing google-places doc is denied (QA-SEC-003 vandalism)', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection('gyms')
      .doc('ChIJ_place_7')
      .set(validGooglePlacesGym('ChIJ_place_7'));
  });

  // Any OTHER authenticated user must not be able to rewrite the name — this
  // is the core catalog-vandalism vector the pin closes.
  const attacker = testEnv.authenticatedContext('attacker');
  await assertFails(
    attacker
      .firestore()
      .collection('gyms')
      .doc('ChIJ_place_7')
      .set({ name: 'VANDALIZED' }, { merge: true }),
  );
});

test('GYM-PLACES-08: update that CHANGES lat/lng of an existing google-places doc is denied (QA-SEC-003 vandalism)', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection('gyms')
      .doc('ChIJ_place_8')
      .set(validGooglePlacesGym('ChIJ_place_8'));
  });

  const attacker = testEnv.authenticatedContext('attacker');
  await assertFails(
    attacker
      .firestore()
      .collection('gyms')
      .doc('ChIJ_place_8')
      .set({ lat: 0, lng: 0 }, { merge: true }),
  );
});

test('GYM-PLACES-09: create is denied when lat is outside geographic range', async () => {
  const athleteA = testEnv.authenticatedContext('athlete-a');
  await assertFails(
    athleteA
      .firestore()
      .collection('gyms')
      .doc('ChIJ_place_9')
      .set({ ...validGooglePlacesGym('ChIJ_place_9'), lat: 999 }),
  );
});

test('GYM-PLACES-10: create is denied when lng is outside geographic range', async () => {
  const athleteA = testEnv.authenticatedContext('athlete-a');
  await assertFails(
    athleteA
      .firestore()
      .collection('gyms')
      .doc('ChIJ_place_10')
      .set({ ...validGooglePlacesGym('ChIJ_place_10'), lng: -200 }),
  );
});

// ---------------------------------------------------------------------------
// routines (user-created) — SCENARIO-600..608
// REQ-USR-004, REQ-USR-008, REQ-USR-009, REQ-USR-012, REQ-USR-013,
// REQ-USR-014, ADR-USR-03, ADR-USR-06.
// ---------------------------------------------------------------------------

/** Helper: base valid user-created routine payload for athlete A. */
const validUserCreated = (uid) => ({
  source: 'user-created',
  createdBy: uid,
  visibility: 'private',
  name: 'Mi rutina',
  split: 'Full Body',
  level: 'beginner',
  days: [],
  status: 'active',
  createdAt: new Date(), // resolved as timestamp by the emulator
});

// SCENARIO-600: owner create succeeds (all 6 conditions satisfied).
test('SCENARIO-600: owner can create user-created routine with valid payload', async () => {
  const athleteA = testEnv.authenticatedContext('athlete-a');
  await assertSucceeds(
    athleteA.firestore().collection('routines').doc('r-600').set(
      validUserCreated('athlete-a'),
    ),
  );
});

// SCENARIO-601: spoofed createdBy is denied (REQ-USR-014).
test('SCENARIO-601: spoofed createdBy is denied', async () => {
  const athleteA = testEnv.authenticatedContext('athlete-a');
  await assertFails(
    athleteA.firestore().collection('routines').doc('r-601').set({
      ...validUserCreated('athlete-a'),
      createdBy: 'athlete-b', // impersonation attempt
    }),
  );
});

// SCENARIO-602: visibility=public is now ALLOWED on user-created create.
//
// REQ-USR-012 originally clamped athlete-authored routines to `private`.
// d1d37ea2 (2026-07-07, "public profile tabs — RUTINAS PÚBLICAS + share
// toggle", #297) reopened it: CREATE branch 2 accepts
// `visibility in ['private', 'public']` so the athlete can opt in at create
// time. `shared` stays trainer-assigned only — SCENARIO-602b pins that the
// clamp is still a clamp and not an anything-goes field.
test('SCENARIO-602: visibility=public is allowed on user-created create', async () => {
  const athleteA = testEnv.authenticatedContext('athlete-a');
  await assertSucceeds(
    athleteA.firestore().collection('routines').doc('r-602').set({
      ...validUserCreated('athlete-a'),
      visibility: 'public',
    }),
  );
});

// SCENARIO-602b: visibility=shared is still denied on user-created create —
// `shared` is the trainer-assigned concept (CREATE branch 1), and letting an
// athlete mint it here would put a self-authored doc into the branch of the
// read rule that serves trainer-assigned plans.
test('SCENARIO-602b: visibility=shared is denied on user-created create', async () => {
  const athleteA = testEnv.authenticatedContext('athlete-a');
  await assertFails(
    athleteA.firestore().collection('routines').doc('r-602b').set({
      ...validUserCreated('athlete-a'),
      visibility: 'shared',
    }),
  );
});

// SCENARIO-603: assignedBy present is denied (REQ-USR-004).
test('SCENARIO-603: assignedBy present on user-created create is denied', async () => {
  const athleteA = testEnv.authenticatedContext('athlete-a');
  await assertFails(
    athleteA.firestore().collection('routines').doc('r-603').set({
      ...validUserCreated('athlete-a'),
      assignedBy: 'trainer-x',
    }),
  );
});

// SCENARIO-604: assignedTo present is denied (REQ-USR-004).
test('SCENARIO-604: assignedTo present on user-created create is denied', async () => {
  const athleteA = testEnv.authenticatedContext('athlete-a');
  await assertFails(
    athleteA.firestore().collection('routines').doc('r-604').set({
      ...validUserCreated('athlete-a'),
      assignedTo: 'athlete-z',
    }),
  );
});

// SCENARIO-605: owner reads own private user-created routine — succeeds.
test('SCENARIO-605: owner can read their own user-created routine', async () => {
  // Seed directly to bypass rules.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('routines').doc('r-605').set(
      validUserCreated('athlete-a'),
    );
  });

  const athleteA = testEnv.authenticatedContext('athlete-a');
  await assertSucceeds(
    athleteA.firestore().collection('routines').doc('r-605').get(),
  );
});

// SCENARIO-606: other auth'd user cannot read another's private user-created
// routine (REQ-USR-007, REQ-USR-008).
test('SCENARIO-606: non-owner cannot read another user\'s private user-created routine', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('routines').doc('r-606').set(
      validUserCreated('athlete-a'),
    );
  });

  const athleteB = testEnv.authenticatedContext('athlete-b');
  await assertFails(
    athleteB.firestore().collection('routines').doc('r-606').get(),
  );
});

// SCENARIO-609: `get` on a NON-EXISTENT routine resolves to an empty snapshot
// instead of PERMISSION_DENIED.
//
// Regression: the read rule used to dereference `resource.data` with no
// existence guard. On a missing doc `resource` is null, so the rule evaluation
// itself errored and the read came back DENIED — meaning `getById()` on a
// deleted routine THREW instead of returning null, and the client's
// `if (!snap.exists)` guard was dead code. That blanked the muscle-distribution
// radars: the providers resolve the routine of every scanned session, so one
// stale session pointing at a deleted routine failed the whole chart.
test('SCENARIO-609: reading a non-existent routine returns empty, not denied',
  async () => {
    const athleteA = testEnv.authenticatedContext('athlete-a');
    const snap = await assertSucceeds(
      athleteA.firestore().collection('routines').doc('r-609-nonexistent').get(),
    );
    expect(snap.exists).toBe(false);
  });

// SCENARIO-610: the existence guard does NOT bypass authentication.
//
// `resource == null` is the leftmost disjunct, so the ONLY thing standing
// between it and an anonymous existence oracle is the `request.auth != null`
// conjunct. If someone ever reorders or relaxes that, an unauthenticated client
// could probe which routine ids exist. This is the boundary the new disjunct
// could actually have broken — SCENARIO-606 already covered "other user's
// private routine", so re-testing that would add nothing.
test('SCENARIO-610: UNAUTHENTICATED read of a non-existent routine is denied',
  async () => {
    const anon = testEnv.unauthenticatedContext();
    await assertFails(
      anon.firestore().collection('routines').doc('r-610-nonexistent').get(),
    );
  });

// SCENARIO-611: an EXISTING trainer-template whose owner revoked athlete
// sharing is still denied.
//
// This is the case that justifies RoutineRepository.getByIdIfVisible absorbing
// `permission-denied` (not just `not-found`): an athlete trains from a
// trainer-template while `sharedTemplatesWithAthletes == true`; the trainer
// later flips it to false; the athlete's old sessions reference that routineId
// forever. The doc EXISTS, so the existence guard does not apply — the read
// must still be denied, and the client must degrade rather than blank the radar.
test('SCENARIO-611: trainer-template is denied once sharing is revoked',
  async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      // NOTE: hoist `ctx.firestore()` — calling it twice inside the same
      // withSecurityRulesDisabled block throws "Firestore has already been
      // started and its settings can no longer be changed".
      const db = ctx.firestore();
      await db.collection('userPublicProfiles').doc('trainer-x').set({
        sharedTemplatesWithAthletes: false,
      });
      await db.collection('routines').doc('r-611').set({
        source: 'trainer-template',
        assignedBy: 'trainer-x',
        visibility: 'private',
        name: 'Plantilla del PF',
        level: 'beginner',
        days: [],
        createdAt: new Date(),
      });
    });

    const athleteA = testEnv.authenticatedContext('athlete-a');
    await assertFails(
      athleteA.firestore().collection('routines').doc('r-611').get(),
    );
  });

// SCENARIO-607: owner can flip status active→archived (REQ-USR-013).
test('SCENARIO-607: owner can update status from active to archived', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('routines').doc('r-607').set(
      validUserCreated('athlete-a'),
    );
  });

  const athleteA = testEnv.authenticatedContext('athlete-a');
  await assertSucceeds(
    athleteA.firestore().collection('routines').doc('r-607').update({
      status: 'archived',
    }),
  );
});

// SCENARIO-608a: owner CAN update name — UPDATE path 2 (REQ-USR-018,
// ADR-USR-03), added by c0bc7cdf (2026-06-09, "editar rutina propia del
// alumno"). Path 1 is still the narrow status-only flip of SCENARIO-607;
// path 2 sits next to it and allows the content fields.
//
// The affectedKeys guard this scenario was written to defend did NOT
// disappear, it moved: path 2's allowlist is
// ['name', 'level', 'days', 'numWeeks', 'visibility']. SCENARIO-608c below
// keeps that edge pinned so the guard cannot rot away unnoticed.
test('SCENARIO-608a: owner can update name field (UPDATE path 2)', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('routines').doc('r-608a').set(
      validUserCreated('athlete-a'),
    );
  });

  const athleteA = testEnv.authenticatedContext('athlete-a');
  await assertSucceeds(
    athleteA.firestore().collection('routines').doc('r-608a').update({
      name: 'Nombre cambiado',
    }),
  );
});

// SCENARIO-608c: `split` is inside path 2's keys().hasOnly() list (the doc
// may carry it) but OUTSIDE its affectedKeys() allowlist — so it is a
// readable, writable-at-create, immutable-at-update field. This is the
// boundary of the widening: prove that path 2 opened `name`/`level`/`days`
// and nothing more.
test('SCENARIO-608c: owner cannot update split field (affectedKeys guard)', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('routines').doc('r-608c').set(
      validUserCreated('athlete-a'),
    );
  });

  const athleteA = testEnv.authenticatedContext('athlete-a');
  await assertFails(
    athleteA.firestore().collection('routines').doc('r-608c').update({
      split: 'Push Pull Legs',
    }),
  );
});

// SCENARIO-608b: non-owner cannot flip status (REQ-USR-009).
test('SCENARIO-608b: non-owner cannot update status of another user\'s routine', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('routines').doc('r-608b').set(
      validUserCreated('athlete-a'),
    );
  });

  const athleteB = testEnv.authenticatedContext('athlete-b');
  await assertFails(
    athleteB.firestore().collection('routines').doc('r-608b').update({
      status: 'archived',
    }),
  );
});

// ---------------------------------------------------------------------------
// routines periodization — SCENARIO-PERIOD-050..054
// REQ-PERIOD-050, REQ-PERIOD-052, REQ-PERIOD-054, REQ-PERIOD-064.
// numWeeks was added to BOTH hasOnly clauses of the three routine UPDATE
// paths (user-owned / trainer-assigned / trainer-template). Executable
// versions of the emulator-deferred Dart stubs in
// test/features/workout/data/routine_rules_test.dart.
// ---------------------------------------------------------------------------

// SCENARIO-PERIOD-050: owner content-update INCLUDING numWeeks is allowed.
test('SCENARIO-PERIOD-050: owner can update content fields including numWeeks', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('routines').doc('r-p050').set({
      ...validUserCreated('athlete-a'),
      numWeeks: 1,
    });
  });

  const athleteA = testEnv.authenticatedContext('athlete-a');
  await assertSucceeds(
    athleteA.firestore().collection('routines').doc('r-p050').update({
      name: 'Plan periodizado',
      numWeeks: 4,
    }),
  );
});

// SCENARIO-PERIOD-051: the affectedKeys trap — a LEGACY doc (no numWeeks
// field) updated by a new client that always sends numWeeks. The key APPEARS
// in the diff, so it counts as affected even at the semantic default 1.
test('SCENARIO-PERIOD-051: numWeeks-only diff on a legacy doc is allowed (affectedKeys trap)', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    // Seeded WITHOUT numWeeks — simulates every pre-periodization doc.
    await ctx.firestore().collection('routines').doc('r-p051').set(
      validUserCreated('athlete-a'),
    );
  });

  const athleteA = testEnv.authenticatedContext('athlete-a');
  await assertSucceeds(
    athleteA.firestore().collection('routines').doc('r-p051').update({
      numWeeks: 1,
    }),
  );
});

// SCENARIO-PERIOD-052: non-owner touching numWeeks is denied.
test('SCENARIO-PERIOD-052: non-owner cannot update numWeeks', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('routines').doc('r-p052').set(
      validUserCreated('athlete-a'),
    );
  });

  const athleteB = testEnv.authenticatedContext('athlete-b');
  await assertFails(
    athleteB.firestore().collection('routines').doc('r-p052').update({
      numWeeks: 4,
    }),
  );
});

// SCENARIO-PERIOD-054: a NEW client creates a routine with numWeeks present
// (Routine.toJson() always serializes it) — the create rule must accept it.
test('SCENARIO-PERIOD-054: owner create with numWeeks present succeeds', async () => {
  const athleteA = testEnv.authenticatedContext('athlete-a');
  await assertSucceeds(
    athleteA.firestore().collection('routines').doc('r-p054').set({
      ...validUserCreated('athlete-a'),
      numWeeks: 4,
    }),
  );
});

// ---------------------------------------------------------------------------
// per-week presence (periodization-week-presence) — SCENARIO-WPRES-RULES-01/02
// REQ-WPRES-005: activeWeeks is nested inside days[].slots[], NOT top-level.
// The existing hasOnly guard on `days` already covers nested mutations.
// VERIFY-don't-assume: these tests confirm no rules change is required.
// ---------------------------------------------------------------------------

// SCENARIO-WPRES-RULES-01: owner update adding activeWeeks inside a slot
// (nested in days) is ALLOWED — existing rules already cover it.
test('SCENARIO-WPRES-RULES-01: owner update adding activeWeeks inside a slot is allowed', async () => {
  // Seed a routine without activeWeeks — simulates a pre-change doc.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('routines').doc('r-wpres-01').set({
      ...validUserCreated('athlete-a'),
      numWeeks: 2,
      days: [
        {
          dayNumber: 1,
          name: 'Day 1',
          slots: [
            {
              exerciseId: 'bench-press',
              exerciseName: 'Bench Press',
              muscleGroup: 'chest',
              targetSets: 3,
              targetRepsMin: 8,
              targetRepsMax: 12,
              restSeconds: 90,
              // No activeWeeks — simulates legacy doc
            },
          ],
        },
      ],
    });
  });

  const athleteA = testEnv.authenticatedContext('athlete-a');
  // Update: add activeWeeks inside a slot nested in days.
  // activeWeeks is NOT a new top-level key — it lives inside days[].slots[].
  // The hasOnly guard checks top-level keys only; days is already allowed.
  await assertSucceeds(
    athleteA.firestore().collection('routines').doc('r-wpres-01').update({
      numWeeks: 2,
      days: [
        {
          dayNumber: 1,
          name: 'Day 1',
          slots: [
            {
              exerciseId: 'bench-press',
              exerciseName: 'Bench Press',
              muscleGroup: 'chest',
              targetSets: 3,
              targetRepsMin: 8,
              targetRepsMax: 12,
              restSeconds: 90,
              activeWeeks: [0], // NEW: presence mask — nested in days, not top-level
            },
          ],
        },
      ],
    }),
  );
});

// SCENARIO-WPRES-RULES-02 (negative control): same update PLUS a bogus
// top-level key is DENIED — hasOnly guard still bites; nothing was loosened.
test('SCENARIO-WPRES-RULES-02: update with bogus top-level key is denied (guard still works)', async () => {
  // Seed a routine.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('routines').doc('r-wpres-02').set({
      ...validUserCreated('athlete-a'),
      numWeeks: 2,
      days: [],
    });
  });

  const athleteA = testEnv.authenticatedContext('athlete-a');
  // Same slot-level activeWeeks mutation PLUS a bogus top-level field.
  // The bogus key is not in hasOnly → must be DENIED.
  await assertFails(
    athleteA.firestore().collection('routines').doc('r-wpres-02').update({
      numWeeks: 2,
      days: [
        {
          dayNumber: 1,
          name: 'Day 1',
          slots: [
            {
              exerciseId: 'bench-press',
              exerciseName: 'Bench Press',
              muscleGroup: 'chest',
              targetSets: 3,
              targetRepsMin: 8,
              targetRepsMax: 12,
              restSeconds: 90,
              activeWeeks: [0],
            },
          ],
        },
      ],
      bogusTopLevelField: 'this should not be allowed', // NOT in hasOnly
    }),
  );
});
