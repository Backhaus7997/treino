'use strict';

/**
 * Firestore Security Rules test suite — posts / friendships / trainer_links /
 * chats structural hardening (rules-hardening Slice D, final slice).
 *
 * Covers:
 *  - post-friendship-model spec: "Posts Update Pins Identity Fields",
 *    "Friendships Create Enforces Pair Shape", "Chats Create Allowlists
 *    Fields".
 *  - coach-link-lifecycle spec: "trainer_links Status Transition Is
 *    Actor-Gated" — NOTE: the spec's literal text uses `'accepted'` as the
 *    target status. VERIFIED WRONG against `trainer_link_status.dart`
 *    (enum: pending/active/paused/terminated — no `accepted`) and
 *    `trainer_link_repository.dart` (`accept()` writes `status: 'active'`).
 *    This suite implements the REAL enum (design.md AD-4), not the spec
 *    literal. See engram sdd/rules-hardening/design (AD-4) + tasks (Learned #2).
 *
 * Field enumerations verified against:
 *  - lib/features/feed/domain/post.dart (Post.toJson shape)
 *  - lib/features/feed/domain/friendship.dart + friendship_repository.dart
 *    (Friendship.toJson shape, sortedDocId convention)
 *  - lib/features/chat/data/chat_repository.dart (getOrCreate create payload)
 *  - lib/features/coach/data/trainer_link_repository.dart (accept/decline/
 *    cancel/terminate/pause/resume — all 6 methods are LIVE code, contrary to
 *    a stale dartdoc comment in trainer_link_status.dart claiming pause/
 *    resume are unexposed)
 *
 * Run via: JAVA_HOME=/opt/homebrew/opt/openjdk@21 bash scripts/test_rules.sh
 * (Requires the Firebase emulator; Firestore only, no Storage needed here.)
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

async function seedPost(postId, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('posts').doc(postId).set(data);
  });
}

async function seedTrainerLink(linkId, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('trainer_links').doc(linkId).set(data);
  });
}

const basePost = {
  id: 'post1',
  authorUid: 'author',
  authorDisplayName: 'Author Name',
  authorAvatarUrl: null,
  authorGymId: 'gymA',
  text: 'leg day',
  routineTag: null,
  privacy: 'public',
  createdAt: new Date(),
};

// ---------------------------------------------------------------------------
// SCENARIO-PFM-POST-01: An author mutates authorGymId to inject a post into
// another gym's feed. [AD-4][REQ:post-friendship-model#Posts Update Pins
// Identity Fields — cross-gym injection]
// ---------------------------------------------------------------------------
test('SCENARIO-PFM-POST-01: author cannot change authorGymId on update (cross-gym injection)', async () => {
  await seedPost('post1', basePost);

  const author = testEnv.authenticatedContext('author');
  await assertFails(
    author.firestore().collection('posts').doc('post1').set(
      { ...basePost, authorGymId: 'gymB' },
    ),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-PFM-POST-02: An author mutates authorUid or authorDisplayName
// (identity forgery). [AD-4][REQ:post-friendship-model#Posts Update Pins
// Identity Fields — identity forgery]
// ---------------------------------------------------------------------------
test('SCENARIO-PFM-POST-02: author cannot change authorUid on update', async () => {
  await seedPost('post1', basePost);

  const author = testEnv.authenticatedContext('author');
  await assertFails(
    author.firestore().collection('posts').doc('post1').set(
      { ...basePost, authorUid: 'someoneElse' },
    ),
  );
});

test('SCENARIO-PFM-POST-02b: author cannot change authorDisplayName on update', async () => {
  await seedPost('post1', basePost);

  const author = testEnv.authenticatedContext('author');
  await assertFails(
    author.firestore().collection('posts').doc('post1').set(
      { ...basePost, authorDisplayName: 'Forged Name' },
    ),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-PFM-POST-03: An author injects an unknown field on update (hasOnly
// allowlist). [AD-4][REQ:post-friendship-model#Posts Update Pins Identity
// Fields]
// ---------------------------------------------------------------------------
test('SCENARIO-PFM-POST-03: author cannot inject an unknown field on update', async () => {
  await seedPost('post1', basePost);

  const author = testEnv.authenticatedContext('author');
  await assertFails(
    author.firestore().collection('posts').doc('post1').set(
      { ...basePost, extraField: 'malicious' },
    ),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-PFM-POST-04: An author edits an allowlisted mutable field (text)
// while identity fields remain unchanged. [AD-4#legit path] — legit-path
// anchor, must stay green through the GREEN step.
// ---------------------------------------------------------------------------
test('SCENARIO-PFM-POST-04: author CAN edit text while identity fields stay unchanged', async () => {
  await seedPost('post1', basePost);

  const author = testEnv.authenticatedContext('author');
  await assertSucceeds(
    author.firestore().collection('posts').doc('post1').set(
      { ...basePost, text: 'leg day, take 2' },
    ),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-PFM-POST-04b: An author edits privacy/routineTag/authorAvatarUrl
// (the remaining allowlisted mutable fields). [AD-4#legit path]
// ---------------------------------------------------------------------------
test('SCENARIO-PFM-POST-04b: author CAN edit privacy, routineTag and authorAvatarUrl', async () => {
  await seedPost('post1', basePost);

  const author = testEnv.authenticatedContext('author');
  await assertSucceeds(
    author.firestore().collection('posts').doc('post1').set(
      {
        ...basePost,
        privacy: 'friends',
        routineTag: 'push-day',
        authorAvatarUrl: 'https://example.com/avatar.jpg',
      },
    ),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-PFM-FRIEND-01: A user injects a malformed friendship with a
// duplicate member (size 2 but not distinct). [AD-4][REQ:post-friendship-
// model#Friendships Create Enforces Pair Shape]
// ---------------------------------------------------------------------------
test('SCENARIO-PFM-FRIEND-01: requester cannot create a friendship with duplicate members', async () => {
  const requester = testEnv.authenticatedContext('requester');
  await assertFails(
    requester.firestore().collection('friendships').doc('requester_requester').set({
      id: 'requester_requester',
      uidA: 'requester',
      uidB: 'requester',
      status: 'pending',
      requesterId: 'requester',
      members: ['requester', 'requester'],
      createdAt: new Date(),
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-PFM-FRIEND-01b: A user injects a friendship with a members array
// of size != 2 (e.g. 3 members, extra forged entry). [AD-4]
// ---------------------------------------------------------------------------
test('SCENARIO-PFM-FRIEND-01b: requester cannot create a friendship with 3 members', async () => {
  const requester = testEnv.authenticatedContext('requester');
  await assertFails(
    requester.firestore().collection('friendships').doc('requester_target').set({
      id: 'requester_target',
      uidA: 'requester',
      uidB: 'target',
      status: 'pending',
      requesterId: 'requester',
      members: ['requester', 'target', 'extra'],
      createdAt: new Date(),
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-PFM-FRIEND-02: A user creates a friendship doc with a mismatched
// doc-id (not the sortedDocId of the two members). [AD-4][REQ:post-
// friendship-model#Friendships Create Enforces Pair Shape — mismatched doc-id]
// ---------------------------------------------------------------------------
test('SCENARIO-PFM-FRIEND-02: requester cannot create a friendship under a doc-id that does not match sortedDocId(members)', async () => {
  const requester = testEnv.authenticatedContext('requester');
  await assertFails(
    requester.firestore().collection('friendships').doc('not-the-sorted-id').set({
      id: 'not-the-sorted-id',
      uidA: 'requester',
      uidB: 'target',
      status: 'pending',
      requesterId: 'requester',
      members: ['requester', 'target'].sort(),
      createdAt: new Date(),
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-PFM-FRIEND-03: A legitimate friend request (pending) is created
// under the correct sortedDocId. [AD-4#legit path] — legit-path anchor.
// ---------------------------------------------------------------------------
test('SCENARIO-PFM-FRIEND-03: requester CAN create a pending friendship under the correct sortedDocId', async () => {
  const members = ['requester', 'target'].sort();
  const docId = `${members[0]}_${members[1]}`;

  const requester = testEnv.authenticatedContext('requester');
  await assertSucceeds(
    requester.firestore().collection('friendships').doc(docId).set({
      id: docId,
      uidA: members[0],
      uidB: members[1],
      status: 'pending',
      requesterId: 'requester',
      members,
      createdAt: new Date(),
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-PFM-FRIEND-03b: REGRESSION — the pre-existing public-profile
// auto-accept create path (status: 'accepted' at create time, gated by
// userPublicProfiles.isProfilePublic) must keep working once the pair-shape
// checks are added. [RISK: friendships create already has a second status
// branch not covered by design.md's simplified snippet — must AND-wrap, not
// replace]
// ---------------------------------------------------------------------------
test('SCENARIO-PFM-FRIEND-03b: requester CAN auto-accept-create against a public-profile target', async () => {
  const members = ['requester', 'publictarget'].sort();
  const docId = `${members[0]}_${members[1]}`;

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('userPublicProfiles').doc('publictarget').set({
      uid: 'publictarget',
      isProfilePublic: true,
    });
  });

  const requester = testEnv.authenticatedContext('requester');
  await assertSucceeds(
    requester.firestore().collection('friendships').doc(docId).set({
      id: docId,
      uidA: members[0],
      uidB: members[1],
      status: 'accepted',
      requesterId: 'requester',
      members,
      createdAt: new Date(),
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-PFM-CHAT-01: A member seeds a forged lastRead map at chat
// creation. [AD-4][REQ:post-friendship-model#Chats Create Allowlists Fields]
// ---------------------------------------------------------------------------
test('SCENARIO-PFM-CHAT-01: creator cannot seed a forged lastRead at chat creation', async () => {
  const creator = testEnv.authenticatedContext('uidA');
  await assertFails(
    creator.firestore().collection('chats').doc('uidA_uidB').set({
      members: ['uidA', 'uidB'],
      createdAt: new Date(),
      lastRead: { uidA: new Date(), uidB: new Date('2000-01-01') },
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-PFM-CHAT-01b: A member seeds an arbitrary unknown field at chat
// creation. [AD-4]
// ---------------------------------------------------------------------------
test('SCENARIO-PFM-CHAT-01b: creator cannot seed an unknown field at chat creation', async () => {
  const creator = testEnv.authenticatedContext('uidA');
  await assertFails(
    creator.firestore().collection('chats').doc('uidA_uidB').set({
      members: ['uidA', 'uidB'],
      createdAt: new Date(),
      lastMessageText: 'forged preview',
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-PFM-CHAT-02: A member creates a chat with only the allowlisted
// fields. [AD-4#legit path] — legit-path anchor, unchanged from current
// behavior.
// ---------------------------------------------------------------------------
test('SCENARIO-PFM-CHAT-02: creator CAN create a chat with only chatId, members, createdAt', async () => {
  const creator = testEnv.authenticatedContext('uidA');
  await assertSucceeds(
    creator.firestore().collection('chats').doc('uidA_uidB').set({
      chatId: 'uidA_uidB',
      members: ['uidA', 'uidB'],
      createdAt: new Date(),
    }),
  );
});

// ---------------------------------------------------------------------------
// trainer_links actor-gated status transitions.
// REAL enum: pending/active/paused/terminated (NOT 'accepted' — see header).
// ---------------------------------------------------------------------------

// SCENARIO-CLL-01: An athlete self-accepts their own pending link request
// (pending -> active) without trainer consent. [AD-4][REQ:coach-link-
// lifecycle#trainer_links Status Transition Is Actor-Gated — self-accept]
test('SCENARIO-CLL-01: athlete cannot self-accept their own pending link (pending -> active)', async () => {
  await seedTrainerLink('link1', {
    trainerId: 'coach',
    athleteId: 'athlete',
    status: 'pending',
    requestedAt: new Date(),
  });

  const athlete = testEnv.authenticatedContext('athlete');
  await assertFails(
    athlete.firestore().collection('trainer_links').doc('link1').update({
      status: 'active',
      acceptedAt: new Date(),
    }),
  );
});

// SCENARIO-CLL-02: The named trainer accepts a pending link request
// (pending -> active). [AD-4#legit path — accept()]
test('SCENARIO-CLL-02: trainer CAN accept a pending link (pending -> active)', async () => {
  await seedTrainerLink('link2', {
    trainerId: 'coach',
    athleteId: 'athlete',
    status: 'pending',
    requestedAt: new Date(),
    sharedWithTrainer: false,
  });

  const coach = testEnv.authenticatedContext('coach');
  await assertSucceeds(
    coach.firestore().collection('trainer_links').doc('link2').update({
      status: 'active',
      acceptedAt: new Date(),
    }),
  );
});

// SCENARIO-CLL-03: The trainer declines a pending link request
// (pending -> terminated). [AD-4#legit path — decline()]
test('SCENARIO-CLL-03: trainer CAN decline a pending link (pending -> terminated)', async () => {
  await seedTrainerLink('link3', {
    trainerId: 'coach',
    athleteId: 'athlete',
    status: 'pending',
    requestedAt: new Date(),
    sharedWithTrainer: false,
  });

  const coach = testEnv.authenticatedContext('coach');
  await assertSucceeds(
    coach.firestore().collection('trainer_links').doc('link3').update({
      status: 'terminated',
      terminatedAt: new Date(),
      terminationReason: 'declined',
    }),
  );
});

// SCENARIO-CLL-04: The athlete cancels their own pending link request
// (pending -> terminated). [AD-4#legit path — cancel()]
test('SCENARIO-CLL-04: athlete CAN cancel their own pending link (pending -> terminated)', async () => {
  await seedTrainerLink('link4', {
    trainerId: 'coach',
    athleteId: 'athlete',
    status: 'pending',
    requestedAt: new Date(),
    sharedWithTrainer: false,
  });

  const athlete = testEnv.authenticatedContext('athlete');
  await assertSucceeds(
    athlete.firestore().collection('trainer_links').doc('link4').update({
      status: 'terminated',
      terminatedAt: new Date(),
      terminationReason: 'cancelled-by-athlete',
    }),
  );
});

// SCENARIO-CLL-05: The trainer pauses an active link (active -> paused).
// [AD-4#legit path — pause()]
test('SCENARIO-CLL-05: trainer CAN pause an active link (active -> paused)', async () => {
  await seedTrainerLink('link5', {
    trainerId: 'coach',
    athleteId: 'athlete',
    status: 'active',
    requestedAt: new Date(),
    acceptedAt: new Date(),
    sharedWithTrainer: false,
  });

  const coach = testEnv.authenticatedContext('coach');
  await assertSucceeds(
    coach.firestore().collection('trainer_links').doc('link5').update({
      status: 'paused',
      pausedAt: new Date(),
    }),
  );
});

// SCENARIO-CLL-05b: The athlete CANNOT pause an active link — pause/resume
// are trainer-only actions. [AD-4]
test('SCENARIO-CLL-05b: athlete cannot pause an active link (active -> paused)', async () => {
  await seedTrainerLink('link5b', {
    trainerId: 'coach',
    athleteId: 'athlete',
    status: 'active',
    requestedAt: new Date(),
    acceptedAt: new Date(),
    sharedWithTrainer: false,
  });

  const athlete = testEnv.authenticatedContext('athlete');
  await assertFails(
    athlete.firestore().collection('trainer_links').doc('link5b').update({
      status: 'paused',
      pausedAt: new Date(),
    }),
  );
});

// SCENARIO-CLL-06: The trainer resumes a paused link (paused -> active).
// [AD-4#legit path — resume()]
test('SCENARIO-CLL-06: trainer CAN resume a paused link (paused -> active)', async () => {
  await seedTrainerLink('link6', {
    trainerId: 'coach',
    athleteId: 'athlete',
    status: 'paused',
    requestedAt: new Date(),
    acceptedAt: new Date(),
    pausedAt: new Date(),
    sharedWithTrainer: false,
  });

  const coach = testEnv.authenticatedContext('coach');
  await assertSucceeds(
    coach.firestore().collection('trainer_links').doc('link6').update({
      status: 'active',
      pausedAt: null,
    }),
  );
});

// SCENARIO-CLL-07: Either member terminates an active link (active ->
// terminated). [AD-4#legit path — terminate() by trainer]
test('SCENARIO-CLL-07: trainer CAN terminate an active link (active -> terminated)', async () => {
  await seedTrainerLink('link7', {
    trainerId: 'coach',
    athleteId: 'athlete',
    status: 'active',
    requestedAt: new Date(),
    acceptedAt: new Date(),
    sharedWithTrainer: false,
  });

  const coach = testEnv.authenticatedContext('coach');
  await assertSucceeds(
    coach.firestore().collection('trainer_links').doc('link7').update({
      status: 'terminated',
      terminatedAt: new Date(),
    }),
  );
});

// SCENARIO-CLL-07b: Either member terminates an active link (active ->
// terminated). [AD-4#legit path — terminate() by athlete]
test('SCENARIO-CLL-07b: athlete CAN terminate an active link (active -> terminated)', async () => {
  await seedTrainerLink('link7b', {
    trainerId: 'coach',
    athleteId: 'athlete',
    status: 'active',
    requestedAt: new Date(),
    acceptedAt: new Date(),
    sharedWithTrainer: false,
  });

  const athlete = testEnv.authenticatedContext('athlete');
  await assertSucceeds(
    athlete.firestore().collection('trainer_links').doc('link7b').update({
      status: 'terminated',
      terminatedAt: new Date(),
    }),
  );
});

// SCENARIO-CLL-07c: Either member terminates a paused link (paused ->
// terminated). [AD-4#legit path — terminate() over paused]
test('SCENARIO-CLL-07c: trainer CAN terminate a paused link (paused -> terminated)', async () => {
  await seedTrainerLink('link7c', {
    trainerId: 'coach',
    athleteId: 'athlete',
    status: 'paused',
    requestedAt: new Date(),
    acceptedAt: new Date(),
    pausedAt: new Date(),
    sharedWithTrainer: false,
  });

  const coach = testEnv.authenticatedContext('coach');
  await assertSucceeds(
    coach.firestore().collection('trainer_links').doc('link7c').update({
      status: 'terminated',
      terminatedAt: new Date(),
    }),
  );
});

// SCENARIO-CLL-08: An attacker (non-member) cannot flip any transition on a
// link they are not party to. [AD-4] — pre-existing member gate, reasserted.
test('SCENARIO-CLL-08: a non-member cannot accept a pending link', async () => {
  await seedTrainerLink('link8', {
    trainerId: 'coach',
    athleteId: 'athlete',
    status: 'pending',
    requestedAt: new Date(),
    sharedWithTrainer: false,
  });

  const attacker = testEnv.authenticatedContext('attacker');
  await assertFails(
    attacker.firestore().collection('trainer_links').doc('link8').update({
      status: 'active',
      acceptedAt: new Date(),
    }),
  );
});

// SCENARIO-CLL-09: The athlete retains exclusive control of
// sharedWithTrainer — pre-existing privacy gate, unaffected by this change.
// [REQ:coach-link-lifecycle#trainer_links Status Transition Is Actor-Gated —
// sharedWithTrainer]
test('SCENARIO-CLL-09: trainer cannot flip sharedWithTrainer on an active link', async () => {
  await seedTrainerLink('link9', {
    trainerId: 'coach',
    athleteId: 'athlete',
    status: 'active',
    requestedAt: new Date(),
    acceptedAt: new Date(),
    sharedWithTrainer: false,
  });

  const coach = testEnv.authenticatedContext('coach');
  await assertFails(
    coach.firestore().collection('trainer_links').doc('link9').update({
      sharedWithTrainer: true,
    }),
  );
});

// SCENARIO-CLL-09b: The athlete CAN flip sharedWithTrainer (no status
// change) — same-status branch of the actor-gate must not block it.
test('SCENARIO-CLL-09b: athlete CAN flip sharedWithTrainer on their own active link', async () => {
  await seedTrainerLink('link9b', {
    trainerId: 'coach',
    athleteId: 'athlete',
    status: 'active',
    requestedAt: new Date(),
    acceptedAt: new Date(),
    sharedWithTrainer: false,
  });

  const athlete = testEnv.authenticatedContext('athlete');
  await assertSucceeds(
    athlete.firestore().collection('trainer_links').doc('link9b').update({
      sharedWithTrainer: true,
    }),
  );
});
