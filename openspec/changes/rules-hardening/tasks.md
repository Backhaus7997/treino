# Tasks: rules-hardening — close the systemic Firestore/Storage authz gap

> Decomposes `design.md` (AD-1..AD-6) into 4 chained, independently shippable PRs,
> in ship order per AD-6: **A (Storage) → B (reviews+trainerPublicProfiles) →
> C (coach-collections) → D (posts/friendships/trainer_links/chats)**. Every rule
> change follows RED (write the failing `assertFails`/`assertSucceeds` test against
> the CURRENT loose rule) → GREEN (tighten the rule so RED goes green) — this is the
> project's Strict-TDD stack for rules work (`scripts/rules_test/`, NOT
> `functions/src/__tests__/`, which uses the Admin SDK and bypasses rules).
>
> Traceability tags: `[AD-n]` = design.md Architecture Decision; `[REQ:<spec>#<n>]` =
> spec requirement (numbered per spec file, in read order); `[RISK:<n>]` = design.md
> Risks table row.

## Pre-flight (spec/design conflicts found during read — resolve before Slice work)

- [ ] **0.1** `[BLOCKER-DOC]` Flag two spec-vs-design divergences to the user/reviewer
      before writing any Slice B/C/D test (do NOT silently pick one):
      1. **Slice C role-vs-link scope conflict.** `specs/coach-collections-security/spec.md`
         Requirement "Coach-Collection Create Requires Trainer Role + Active Link" and its
         scenario "A trainer with no link to the named athlete forges a record" describe a
         **role + active trainer_links check**. `design.md` AD-1 explicitly CHOSE **role-check
         ONLY** for Slice C (option b) and rejected the full link check for this slice
         (avoids the linkId client shape change). **Resolution for this task list: implement
         per design.md AD-1 (role-check only)**; the two "no link" scenarios in the
         coach-collections-security spec are OUT OF SCOPE for this change and must be
         explicitly marked deferred/not-implemented in the PR C description, not silently
         dropped. If the reviewer wants the spec's stricter behavior, that is a scope change
         requiring a design amendment, not a task-level judgment call.
      2. **coach-link-lifecycle spec status typo.** `specs/coach-link-lifecycle/spec.md` uses
         `'accepted'` as the trainer-link target status. Verified against
         `lib/features/coach/domain/trainer_link_status.dart` (enum: `pending, active, paused,
         terminated` — no `accepted` value exists) and `trainer_link_repository.dart:66`
         (`accept()` writes `status: 'active'`). **The spec is wrong; design.md AD-4 already
         corrected this.** All Slice D trainer_links tests MUST use `'active'`, never
         `'accepted'`. Do not implement the spec's literal scenario text.
- [ ] **0.2** Confirm `athlete_billing` create+update share ONE combined rule block
      (`firestore.rules:867-876`, `allow create, update:`), unlike design's per-slice file
      map which lists it as a `create` line reference only. The Slice C role-gate task for
      this collection must add the role check to the shared block WITHOUT breaking the
      existing `update` path (owner-pin `trainerId == auth.uid` already covers update
      safely — the new role check is a pure narrowing of `create` only if scoped with an
      `is create` predicate, OR proven safe to also apply on `update` because a trainer's
      own role never changes between create and update of their own billing doc). Decide
      and document the exact predicate in task 3.6 below — do not guess in the rule diff.

---

## Slice A — Storage chatMedia (PR A, ships first and alone) — URGENT, isolated

**Files:** `storage.rules` (~54-71), `scripts/rules_test/` (new storage init block +
spec file), `scripts/test_rules.sh` (~29-31). Zero client changes.

- [x] **1.1** `[AD-5]` Extend `scripts/rules_test/` `initializeTestEnvironment` call
      with a `storage: { rules: readFileSync(STORAGE_RULES_PATH, 'utf8'), host: 'localhost',
      port: 9199 }` block alongside the existing `firestore` block (port confirmed in
      `firebase.json:67`; `@firebase/rules-unit-testing ^3.0.0` already a dep). This is
      infra-only — no assertions yet. Decide file placement: extend `rules.test.js`'s
      shared setup/teardown, or a new shared `test-env.js` helper imported by a new
      `chat-media-storage.test.js` sibling spec (design.md AD-5 prefers sibling files per
      slice for isolated review diffs — use `chat-media-storage.test.js`).
      DONE: created `scripts/rules_test/chat-media-storage.test.js` with its own
      `initializeTestEnvironment` (firestore + storage blocks). Also had to pin
      `PROJECT_ID = 'treino-dev'` (not an arbitrary test id) — see 1.9 note on the
      `singleProjectMode` gotcha discovered during GREEN.
- [x] **1.2** `[AD-5]` Update `scripts/test_rules.sh:29-31` — change
      `firebase emulators:exec --only firestore` to `--only firestore,storage` so the
      Storage emulator is up for Slice A's tests. Verify the script still runs `npm test`
      from `scripts/rules_test/` afterward (no other change to the script).
      DONE — also updated the header comment to mention chatMedia/SCENARIO-CHATMEDIA-*.
- [x] **1.3** `[RED]` `[AD-2][REQ:gym-chat-media#Get Requires Chat Membership — non-member
      scenario]` In `chat-media-storage.test.js`, seed a `chats/{chatId}` doc (via
      `withSecurityRulesDisabled`) with `members: [uidA, uidB]`, then write a fake object
      under `chatMedia/{chatId}/{uidA}/file.jpg` via `withSecurityRulesDisabled`. Write a
      test asserting `assertFails` when an authenticated `attacker` (uid NOT in `members`)
      calls `getMetadata()`/`getDownloadURL()` on that path. **Confirm this test FAILS
      against the current rule** (`storage.rules:56`, `allow read: if request.auth != null`
      grants it) before touching the rule — this is the RED checkpoint.
      DONE — confirmed FAILED (assertFails did not fail = exploit reachable) against the
      loose rule via a real emulator run before the GREEN edit. See apply-progress.
- [x] **1.4** `[RED]` `[AD-2][REQ:gym-chat-media#Get Requires Chat Membership —
      unauthenticated]` Same file: assert `assertFails` for a `get` with no auth context
      (`ctx.storage()` with no signed-in user) on the same path. Confirm it currently PASSES
      (already denied by `request.auth != null`) — this one is a non-regression check, not
      new RED; note it explicitly as "already correct" in the test comment.
      DONE — SCENARIO-CHATMEDIA-02, passed on both RED and GREEN runs as expected.
- [x] **1.5** `[RED]` `[AD-2][REQ:gym-chat-media#chatMedia List Denial — both scenarios]`
      Two tests: `attacker.listAll()` on `chatMedia/{chatId}/` → `assertFails`; AND
      `member` (uid IS in `chats/{chatId}.members`) `.listAll()` on the same path →
      `assertFails` (list is unconditionally closed, even for members — per spec). Confirm
      BOTH currently PASS as `assertSucceeds` today (list has no explicit rule, falls
      through to the same permissive `allow read`) — i.e., both are currently ALLOWED,
      so writing them as `assertFails` now is the RED state (they fail against the current
      rule). This is the confirmation step before rule tightening.
      DONE — SCENARIO-CHATMEDIA-03/04, both confirmed RED (failed) before the rule edit.
- [x] **1.6** `[RED]` `[AD-2][REQ:gym-chat-media#Get Requires Chat Membership — member
      scenario]` Assert `assertSucceeds` for `member` (uid IS in `chats/{chatId}.members`)
      calling `get`/`getMetadata()` on `chatMedia/{chatId}/{eitherMemberUid}/file.jpg`.
      This one already passes today (broad `request.auth != null` allows it) — keep it as
      the non-vacuity/legit-path anchor that must STAY green after the GREEN step.
      DONE — SCENARIO-CHATMEDIA-05/05b. Passed pre-fix; briefly regressed to a Storage
      `unauthorized` error mid-fix due to the `singleProjectMode` project-id mismatch
      (see 1.9), fixed by pinning `PROJECT_ID='treino-dev'`, green again post-fix.
- [x] **1.7** `[RED]` `[REQ:gym-chat-media#Write/Delete Unaffected]` Assert `assertSucceeds`
      for the owning uploader's `write` with an allowlisted content-type/size — this is a
      pure regression guard proving Slice A does not touch write/delete. Already passing;
      keep green.
      DONE — SCENARIO-CHATMEDIA-06/07 (write + delete), green throughout.
- [x] **1.8** `[GREEN]` `[AD-2]` Edit `storage.rules:54-71`: split `allow read: if
      request.auth != null;` into `allow get: if request.auth != null && request.auth.uid
      in firestore.get(/databases/(default)/documents/chats/$(chatId)).data.members;` +
      `allow list: if false;`. Use the literal `(default)` database name (Storage rules
      have no `$(database)` wildcard — confirmed in AD-2). Remove the outdated
      "Storage rules cannot call get() on Firestore" comment block (`storage.rules:41-50`)
      and replace with a short note pointing at this membership gate. Leave `write`/`delete`
      untouched.
      DONE — exact syntax used (verbatim, confirmed working against a live emulator):
      `allow get: if request.auth != null && request.auth.uid in firestore.get(/databases/(default)/documents/chats/$(chatId)).data.members;`
      `allow list: if false;`
- [x] **1.9** `[GATE]` Run `scripts/test_rules.sh` (requires `firebase emulators:start`
      or `emulators:exec` per the script) — full suite green, all Slice A tests (1.3-1.7)
      now pass as written (deny tests deny, allow tests allow). Non-vacuity: confirm 1.3
      flips from failing-as-red to passing-as-green, and 1.6/1.7 stayed green throughout.
      DONE, with ONE real gotcha found and fixed: `firebase.json` sets
      `emulators.singleProjectMode: true`, which pins the Storage rules'
      cross-service `firestore.get()` calls to the emulator suite's DEFAULT project
      (`.firebaserc` → `treino-dev`), regardless of the `projectId` passed to
      `initializeTestEnvironment`. The existing `rules.test.js` uses
      `PROJECT_ID='treino-test-rules'` and never hits this because it never crosses
      into Storage. `chat-media-storage.test.js` MUST use `PROJECT_ID='treino-dev'`
      or the member-`get` legit-path tests intermittently fail with a Storage-rules
      "Null value error." (the cross-service get() looks up the seeded chat doc under
      the wrong project and finds nothing). Fixed + documented inline in the test file.
      Full-suite result: `scripts/rules_test/chat-media-storage.test.js` 9/9 passed.
      `scripts/rules_test/rules.test.js` 43/45 passed — the 2 failures
      (SCENARIO-270 inverse, SCENARIO-608a) are PRE-EXISTING on unmodified
      `origin/main` (verified via `git stash` + re-run before restoring this
      branch's changes) — unrelated to Slice A, out of scope for this PR, not a
      regression introduced here.
- [x] **1.10** `[GATE]` Dry-run compile: `firebase deploy --only storage:rules --dry-run`
      (or equivalent `firebase deploy --only firestore:rules,storage:rules --dry-run` if
      the CLI requires both together) compiles with no syntax errors.
      DONE, with a CLI-syntax correction: this project has no named Storage deploy
      targets configured, so `--only storage:rules` errors
      ("Could not find rules for the following storage targets: rules"). The correct
      invocation for this project is `--only storage` (no `:rules` qualifier) or
      `--only firestore:rules,storage`. Ran
      `firebase deploy --only firestore:rules,storage --dry-run --project treino-dev`
      → "rules file storage.rules compiled successfully" +
      "rules file firestore.rules compiled successfully". No deploy executed.
- [ ] **1.11** `[MANUAL]` User's manual step (not automatable by this task list): run
      `firebase deploy --only firestore:rules,storage:rules` to ship PR A. Do this only
      after 1.9 and 1.10 are both green and the PR is merged.

---

## Slice B — reviews + trainerPublicProfiles rating (PR B, ships second)

**Files:** `firestore.rules` reviews create (`:1022-1031`), trainerPublicProfiles
create+update (`:505-522` — currently only pins `uid`, no metric fields exist yet on
this collection), `scripts/rules_test/reviews-links.test.js` (new sibling file). Zero
client changes — review payload already carries `linkId` (`Review.toJson`).

- [ ] **2.1** `[RED]` `[AD-1][REQ:trainer-reviews#Review Create Requires Real Trainer
      Link — forged review]` In `reviews-links.test.js`, seed (via
      `withSecurityRulesDisabled`) a `users/{attacker}` doc (`role: 'athlete'`) and NO
      `trainer_links` doc naming `trainerId == victimTrainer`. Assert `assertFails` when
      `attacker` creates `reviews/{anyId}` with `athleteId: attacker`,
      `trainerId: victimTrainer`, `rating: 1`. **Confirm this currently PASSES as
      assertSucceeds** against `firestore.rules:1025-1031` (today's rule only checks
      `athleteId == auth.uid` + rating bounds — no relationship check) — this is the RED
      confirmation.
- [ ] **2.2** `[RED]` `[AD-1][REQ:trainer-reviews#Review Create Requires Real Trainer
      Link — mismatched doc-id]` Seed an active `trainer_links/{linkId}` (`trainerId:
      coach`, `athleteId: athlete`, `status: 'active'`). Assert `assertFails` when
      `athlete` creates a review under a **random doc-id** (not `${linkId}_${athlete}`)
      with correct body fields. Confirm currently PASSES as `assertSucceeds` (today's
      rule never checks doc-id) — RED confirmation.
- [ ] **2.3** `[RED]` `[AD-1][REQ:trainer-reviews#Review Create Requires Real Trainer
      Link — legit path]` Same seeded link. Assert `assertSucceeds` when `athlete`
      creates `reviews/${linkId}_${athlete}` with `athleteId: athlete`, `trainerId: coach`,
      `linkId: linkId`, `rating` in `[1,5]`. This must stay green through the GREEN step —
      it is the non-vacuity anchor encoding the exact current `Review.toJson` /
      `ReviewNotifierArgs` payload shape.
- [ ] **2.4** `[GREEN]` `[AD-1]` Edit `firestore.rules:1025-1031` reviews `create`: keep
      `athleteId == auth.uid` + rating/comment bounds; ADD `reviewId ==
      request.resource.data.linkId + '_' + request.resource.data.athleteId`, then
      `get(/databases/$(database)/documents/trainer_links/$(request.resource.data.linkId))`
      and assert `link.data.athleteId == request.auth.uid`,
      `link.data.trainerId == request.resource.data.trainerId`,
      `link.data.status in ['active', 'paused']`. Mirror the `get()`-gate idiom already at
      `firestore.rules:389` style (role check via `get()`) applied to a relationship check
      instead of a role.
- [ ] **2.5** `[GATE]` Re-run 2.1-2.3 — 2.1 and 2.2 now `assertFails` (flipped from RED),
      2.3 stays `assertSucceeds`. Suite green for this file.
- [ ] **2.6** `[RED]` `[AD-3][REQ:trainer-reviews#trainerPublicProfiles Rating Fields
      Are CF-Write-Only — forged rating]` Seed `trainerPublicProfiles/{trainer}` with
      `uid: trainer`, `averageRating: 3.5`, `reviewCount: 10` (simulating a prior CF write,
      seeded via `withSecurityRulesDisabled`). Assert `assertFails` when `trainer` (owner)
      updates the doc with `averageRating: 5.0` (different from `resource.data`) via a
      client-style `update` call. Confirm currently PASSES as `assertSucceeds` against
      `firestore.rules:516-518` (today's update rule only pins `uid`) — RED confirmation.
- [ ] **2.7** `[RED]` `[AD-3#Out-of-allowlist field]` NOTE: design.md AD-3 explicitly
      chose NO `hasOnly` allowlist for trainerPublicProfiles (partial-merge coupling-trap
      reasoning) — this diverges from the `trainer-reviews` spec's "Out-of-allowlist field"
      scenario, which assumes a `hasOnly` exists. **Resolution: implement per design.md
      AD-3 (metric pins only, no hasOnly)** — do NOT write a `hasOnly` allowlist test for
      this collection; that scenario is explicitly NOT implemented in this change. Document
      this divergence in the PR B description (same class of issue as pre-flight 0.1).
- [ ] **2.8** `[RED]` `[AD-3#legit field-only update]` Assert `assertSucceeds` when
      `trainer` updates an unrelated existing field (e.g. `trainerBio`) while
      `averageRating`/`reviewCount` remain unchanged from `resource.data`. This passes
      today (no pin exists yet) — keep as the legit-path anchor that must stay green.
- [ ] **2.9** `[RED]` `[AD-3#create-side guard]` Assert `assertFails` when `trainer`
      CREATES `trainerPublicProfiles/{trainer}` (first write) with `averageRating: 5.0`
      seeded at create time. Confirm currently PASSES as `assertSucceeds` against
      `firestore.rules:511-513` (today's create rule only pins `uid`) — RED confirmation.
- [ ] **2.10** `[RED]` `[AD-3#CF bypass]` Document-only (no new assertion): the
      `reviewAggregate` CF write via Admin SDK bypasses rules entirely and needs no
      rules-layer test (per spec's explicit note) — add a code comment in the test file
      referencing this, not a test.
- [ ] **2.11** `[GREEN]` `[AD-3]` Edit `firestore.rules:511-513` (create): ADD
      `&& request.resource.data.get('averageRating', null) == null && request.resource.data
      .get('reviewCount', null) == null`. Edit `:516-518` (update): ADD
      `&& request.resource.data.get('averageRating', null) == resource.data.get
      ('averageRating', null) && request.resource.data.get('reviewCount', null) ==
      resource.data.get('reviewCount', null)`. Mirror the `.get(field, null)` null-safe
      idiom from the `userPublicProfiles` CF-write-only metric pins (`firestore.rules:434-
      468`, the rankings-integrity reference block) — REUSE that idiom's shape, do not
      reinvent it. Explicitly do NOT add a `keys().hasOnly()` allowlist (AD-3 divergence
      from the spec, per task 2.7).
- [ ] **2.12** `[GATE]` Re-run 2.6, 2.8, 2.9 — 2.6 and 2.9 now `assertFails` (flipped),
      2.8 stays `assertSucceeds`. Suite green for this file.
- [ ] **2.13** `[GATE]` Full `scripts/rules_test/` suite green (Slice A + Slice B tests
      together) via `scripts/test_rules.sh`.
- [ ] **2.14** `[GATE]` `firebase deploy --only firestore:rules,storage:rules --dry-run`
      compiles with no syntax errors.
- [ ] **2.15** `[MANUAL]` User's manual step: run
      `firebase deploy --only firestore:rules,storage:rules` to ship PR B, only after
      2.13 and 2.14 are green and the PR is merged.

---

## Slice C — coach-collections create authz (PR C, ships third)

**Files:** `firestore.rules` create rules for `payments` (`:981-984`), `athlete_billing`
(`:871-874`, combined create+update block — see pre-flight 0.2), `measurements`
(`:835-838`), `performance_tests` (`:853-856`), `appointments` (`:795-798`).
Role-check only per design.md AD-1 option b (NOT the full link check — see pre-flight
0.1 divergence from the coach-collections-security spec). Zero client changes.

- [ ] **3.1** `[RED]` `[AD-1][REQ:coach-collections-security#athlete-role forges
      payment]` In a new `coach-collections.test.js`, seed `users/{attacker}` with
      `role: 'athlete'`. Assert `assertFails` when `attacker` creates `payments/{id}`
      with `trainerId: attacker`, `athleteId: victim`. Confirm currently PASSES as
      `assertSucceeds` against `firestore.rules:981-984` (today's rule only checks
      `trainerId == auth.uid` + `athleteId` shape, no role check) — RED confirmation.
      Repeat the identical pattern (seed athlete-role attacker, assert deny, confirm
      current pass) for `athlete_billing` (`:871-874`), `measurements` (`:835-838`),
      `performance_tests` (`:853-856`) — 4 deny tests total in this task.
- [ ] **3.2** `[RED]` `[AD-1][REQ:coach-collections-security#athlete-role forges
      measurement]` Covered inside 3.1's measurements case — no separate task, listed
      here only for spec-scenario traceability (spec names this scenario separately from
      the payments one; same mechanics).
- [ ] **3.3** `[RED]` `[AD-1][REQ:coach-collections-security#trainer with no link
      forges appointment]` **NOT IMPLEMENTED per pre-flight 0.1** — design.md AD-1 chose
      role-check-only for Slice C, so a trainer WITH a real trainer role but NO link to
      the victim can still create a record naming that victim; this is the explicitly
      accepted residual risk (design.md AD-1: "narrower, higher-friction, attributable
      abuse... deferred as a follow-up, NOT silently dropped"). Do NOT write this as an
      `assertFails` test — it will legitimately `assertSucceeds` after the GREEN step.
      Instead, write ONE explicit test asserting `assertSucceeds` for exactly this
      scenario (trainer role, no link, names an arbitrary athleteId) with a code comment
      citing design.md AD-1, so the residual is provably documented in the suite rather
      than silently untested.
- [ ] **3.4** `[RED]` `[AD-1][REQ:coach-collections-security#real linked trainer
      creates legitimate record]` Seed `users/{trainer}` with `role: 'trainer'`. Assert
      `assertSucceeds` for `trainer` creating a `payments`/`athlete_billing`/
      `measurements`/`performance_tests` doc naming any `athleteId` + the ownership field
      (`trainerId`/`recordedBy`) as `trainer`. Already passes today (no role check exists
      yet) — this is the legit-path anchor across all 4 collections; write one
      parametrized test or 4 discrete tests, developer's choice, but all 4 collections
      must be covered.
- [ ] **3.5** `[RED]` `[REQ:coach-collections-security#appointments legacy self-book
      preserved]` `[RISK: appointments legacy self-book branch]` Seed an active
      `trainer_links` linking `athlete` to `trainer` (link doc not strictly required for
      this test since Slice C is role-only, but seed it anyway for realism). Assert
      `assertSucceeds` when `athlete` creates `appointments/{id}` with
      `status: 'confirmed'`, `athleteId: athlete`, `trainerId: trainer` (the
      `athleteId == auth.uid` branch at `firestore.rules:797`). This MUST stay green
      after the GREEN step — confirms the design's explicit risk mitigation: the
      role-gate is added to the TRAINER branch of the appointments create OR-clause only,
      never to the athlete-self-book branch. If the GREEN step's implementation makes
      this test fail, the rule diff is wrong — do not "fix" the test.
- [ ] **3.6** `[GREEN]` `[AD-1]` Edit each collection's create rule to add
      `&& get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role ==
      'trainer'` (the `:389`-equivalent idiom, now confirmed live at
      `firestore.rules:555` in the `gyms` create rule — reuse that exact shape) to:
      - `payments` create (`:981-984`)
      - `athlete_billing` — **combined create+update block** (`:871-874`): per pre-flight
        0.2, scope the role check to CREATE only using
        `(request.resource.data.diff(resource.data).affectedKeys().hasAny(['trainerId'])
        == false)` is over-complex; simpler and correct: Firestore rules support
        `request.method` inspection is NOT available in this rules version's boolean
        context directly, but `resource == null` reliably distinguishes create (no prior
        doc) from update (prior doc exists) in a combined `allow create, update:` block.
        Use `(resource == null || get(...).data.role == 'trainer')` — i.e., only require
        the role check when there is no existing resource (create path); update keeps
        relying on the existing `trainerId == auth.uid` pin alone, unchanged. Document
        this exact predicate choice in the rule comment.
      - `measurements` create (`:835-838`)
      - `performance_tests` create (`:853-856`)
      - `appointments` create (`:795-798`) — add the role check ONLY to the
        `request.resource.data.trainerId == request.auth.uid` disjunct, NOT to the
        `request.resource.data.athleteId == request.auth.uid` disjunct (preserves 3.5).
        Resulting shape: `(request.resource.data.athleteId == request.auth.uid) ||
        (request.resource.data.trainerId == request.auth.uid && get(/databases/$(database)
        /documents/users/$(request.auth.uid)).data.role == 'trainer')`.
- [ ] **3.7** `[GATE]` Re-run 3.1, 3.4, 3.5 — the 4 deny tests in 3.1 now `assertFails`
      (flipped from RED), 3.3's documented-residual test stays `assertSucceeds`, 3.4 and
      3.5 stay `assertSucceeds`. Suite green for this file.
- [ ] **3.8** `[GATE]` Full `scripts/rules_test/` suite green (Slices A+B+C) via
      `scripts/test_rules.sh`.
- [ ] **3.9** `[GATE]` `firebase deploy --only firestore:rules,storage:rules --dry-run`
      compiles with no syntax errors.
- [ ] **3.10** `[MANUAL]` User's manual step: run
      `firebase deploy --only firestore:rules,storage:rules` to ship PR C, only after
      3.8 and 3.9 are green and the PR is merged.

---

## Slice D — allowlists / pins (PR D, ships fourth)

**Files:** `firestore.rules` posts update (`:308-309`), friendships create (`:605-608`),
trainer_links update (`:284-291`), chats create (`:637-641`). Pure structural
hardening, no cross-doc lookups. Zero client changes.

- [ ] **4.1** `[RED]` `[AD-4][REQ:post-friendship-model#Posts Update Pins Identity
      Fields — authorGymId mutation]` In `post-friendship-pins.test.js`, seed a
      `posts/{postId}` owned by `author` with a known `authorGymId`. Assert `assertFails`
      when `author` updates the post with a DIFFERENT `authorGymId`. Confirm currently
      PASSES as `assertSucceeds` against `firestore.rules:308-309` (today's update rule
      only checks `auth.uid == resource.data.authorUid`, no field pins) — RED
      confirmation.
- [ ] **4.2** `[RED]` `[AD-4][REQ:post-friendship-model#Posts Update Pins Identity
      Fields — authorUid/authorDisplayName mutation]` Same seeded post. Assert
      `assertFails` when `author` updates with a different `authorUid` OR
      `authorDisplayName`. Confirm currently PASSES as `assertSucceeds` — RED
      confirmation.
- [ ] **4.3** `[RED]` `[AD-4][REQ:post-friendship-model#Posts Update Pins Identity
      Fields — legit edit]` Assert `assertSucceeds` when `author` updates only `text` (or
      `routineTag`/`privacy`/`authorAvatarUrl`) while `authorUid`/`authorGymId`/
      `authorDisplayName` remain unchanged. Already passes today — legit-path anchor,
      must stay green. Payload MUST enumerate the exact `Post.toJson` superset (`id,
      authorUid, authorDisplayName, authorAvatarUrl, authorGymId, text, routineTag,
      privacy, createdAt`) per design.md AD-4 — verify against `post.dart` `toJson`
      before writing this test, do not assume the design's list is stale.
- [ ] **4.4** `[GREEN]` `[AD-4]` Edit `firestore.rules:308-309` posts `update`: ADD
      `request.resource.data.keys().hasOnly(['id','authorUid','authorDisplayName',
      'authorAvatarUrl','authorGymId','text','routineTag','privacy','createdAt'])` +
      pins `request.resource.data.authorUid == resource.data.authorUid`,
      `request.resource.data.authorGymId == resource.data.authorGymId`,
      `request.resource.data.authorDisplayName == resource.data.authorDisplayName`. Keep
      the existing `auth.uid == resource.data.authorUid` ownership check. Leave `create`
      unchanged (already pins `authorUid == auth.uid` at `:304-305`).
- [ ] **4.5** `[GATE]` Re-run 4.1-4.3 — 4.1 and 4.2 now `assertFails`, 4.3 stays
      `assertSucceeds`.
- [ ] **4.6** `[RED]` `[AD-4][REQ:post-friendship-model#Friendships Create Enforces
      Pair Shape — malformed members]` Assert `assertFails` when `requester` creates a
      `friendships` doc with a duplicate uid in `members`, and separately with
      `members.size() != 2`. Confirm currently PASSES as `assertSucceeds` against
      `firestore.rules:605-608` (today's create rule only checks `requesterId`, `status`,
      `auth.uid in members` — no size/distinctness check) — RED confirmation. Two
      sub-cases (duplicate, wrong size) in one task.
- [ ] **4.7** `[RED]` `[AD-4][REQ:post-friendship-model#Friendships Create Enforces
      Pair Shape — mismatched doc-id]` Assert `assertFails` when `requester` creates a
      valid 2-member, distinct-member `friendships` doc under an id that does NOT match
      the deterministic `members[0] + '_' + members[1]` pin (sorted ascending, mirroring
      the `chats` doc-id pin at `:640-641`). Confirm currently PASSES — RED confirmation.
- [ ] **4.8** `[RED]` `[AD-4][REQ:post-friendship-model#Friendships Create Enforces
      Pair Shape — legit request]` Assert `assertSucceeds` for a correctly-shaped
      request: `members: [requester, target]` sorted ascending, distinct, size 2,
      `status: 'pending'`, `requesterId: requester`, doc-id ==
      `members[0] + '_' + members[1]`. Verify this matches
      `friendship_repository.dart:35-36`'s actual write shape (sorted members) before
      writing — confirm the repository, do not assume design.md's citation is current.
      Legit-path anchor, must stay green.
- [ ] **4.9** `[GREEN]` `[AD-4]` Edit `firestore.rules:605-608` friendships `create`:
      ADD `request.resource.data.members.size() == 2`,
      `request.resource.data.members[0] != request.resource.data.members[1]`,
      `friendshipId == request.resource.data.members[0] + '_' + request.resource.data
      .members[1]`, `request.resource.data.members[0] < request.resource.data.members[1]`.
      Keep existing `requesterId`/`status`/`auth.uid in members` checks. Leave `update`
      (`:612-617`) unchanged (already pins `requesterId`/`members` + blocks self-accept).
- [ ] **4.10** `[GATE]` Re-run 4.6-4.8 — 4.6 and 4.7 now `assertFails`, 4.8 stays
      `assertSucceeds`.
- [ ] **4.11** `[RED]` `[AD-4][REQ:coach-link-lifecycle#trainer_links Status Transition
      Is Actor-Gated — athlete self-accept]` **Use `status: 'active'`, NOT `'accepted'`
      — see pre-flight 0.1.** In `trainer-links-transitions.test.js`, seed a
      `trainer_links/{linkId}` with `status: 'pending'`, `athleteId: athlete`,
      `trainerId: coach`. Assert `assertFails` when `athlete` updates the doc to
      `status: 'active'`. Confirm currently PASSES as `assertSucceeds` against
      `firestore.rules:284-291` (today's update rule lets either member set any status) —
      RED confirmation.
- [ ] **4.12** `[RED]` `[AD-4#trainer accepts pending link]` Same seeded link. Assert
      `assertSucceeds` when `coach` updates the doc to `status: 'active'` with
      `trainerId`/`athleteId`/`requestedAt` unchanged (+ `acceptedAt` added, per
      `trainer_link_repository.dart:65-68`'s `accept()` payload — verify this field before
      writing the test body). Already passes today — legit-path anchor for the
      pending→active-by-trainer transition, must stay green.
- [ ] **4.13** `[RED]` `[AD-4#either member terminates]` Seed a link with
      `status: 'active'`. Assert `assertSucceeds` when EITHER `athlete` OR `coach` updates
      to `status: 'terminated'` (+ `terminatedAt`, optionally `terminationReason` per
      `terminate()`/`decline()`/`cancel()` payloads). Two sub-cases (athlete-terminates,
      trainer-terminates). Already passes — legit-path anchor, must stay green.
- [ ] **4.14** `[RED]` `[AD-4#pending→terminated by either]` Seed `status: 'pending'`.
      Assert `assertSucceeds` when either `coach` (decline) or `athlete` (cancel) updates
      to `status: 'terminated'`. Already passes — legit-path anchor for this specific
      transition, must stay green after the actor-gate is added (per design.md AD-4 table:
      this transition stays open to either member).
- [ ] **4.15** `[RED]` `[AD-4#active↔paused trainer-only]` Seed `status: 'active'`.
      Assert `assertFails` when `athlete` updates to `status: 'paused'`. Assert
      `assertSucceeds` when `coach` updates to `status: 'paused'` (+ `pausedAt`, per
      `pause()`). Then seed `status: 'paused'` and assert `assertSucceeds` when `coach`
      resumes to `status: 'active'` (pausedAt cleared, per `resume()`), and `assertFails`
      when `athlete` attempts the same resume. Confirm the deny sub-cases currently PASS
      as `assertSucceeds` (today's rule has no actor gate at all) — RED confirmation for
      those two.
- [ ] **4.16** `[RED]` `[REQ:coach-link-lifecycle#athlete exclusive sharedWithTrainer]`
      Assert `assertFails` when `coach` attempts to change `sharedWithTrainer` on an
      active link (pre-existing gate at `firestore.rules:290-291`, unaffected by this
      change) — pure regression guard, already passes as a deny, must stay a deny after
      the GREEN step below.
- [ ] **4.17** `[GREEN]` `[AD-4]` Edit `firestore.rules:284-291` trainer_links `update`:
      keep the existing identity pins (`trainerId`/`athleteId`/`requestedAt` immutable)
      and the `sharedWithTrainer` athlete-exclusive gate. ADD the actor-gated status-
      transition OR-clause from design.md AD-4 verbatim (no-status-change passthrough;
      pending→active trainer-only; pending→terminated either member; active↔paused
      trainer-only; active/paused→terminated either member). Do NOT add a `hasOnly` —
      the repo's partial `.update({...})` maps carry conditional optional fields
      (`acceptedAt`/`pausedAt`/`terminatedAt`/`terminationReason`) that a `hasOnly` would
      fight (per design.md AD-4 explicit no-hasOnly call for this collection).
- [ ] **4.18** `[GATE]` Re-run 4.11-4.16 — 4.11 and the two deny sub-cases in 4.15 now
      `assertFails` (flipped from RED); 4.12, 4.13, 4.14, the two allow sub-cases in 4.15,
      and 4.16 all stay in their original state (green allow / green deny respectively).
      This is the highest-risk gate in Slice D — the full transition table must be
      exercised, not just the headline self-accept case.
- [ ] **4.19** `[RED]` `[AD-4][REQ:post-friendship-model#Chats Create Allowlists
      Fields]` Seed nothing extra. Assert `assertFails` when `creator` (one of the two
      `members`) creates `chats/{chatId}` including a `lastRead` field in the initial
      create payload (in addition to the valid `members`/`createdAt` shape). Confirm
      currently PASSES as `assertSucceeds` against `firestore.rules:637-641` (today's
      create rule has no field allowlist) — RED confirmation.
- [ ] **4.20** `[RED]` `[AD-4#chats create legit path]` Assert `assertSucceeds` for
      `creator` creating `chats/{chatId}` with only `chatId`/`members`/`createdAt`
      (`chat_repository.dart:66-70`'s exact write shape — verify before writing), matching
      the existing `members.size()==2`/sort/doc-id pins. Already passes — legit-path
      anchor, must stay green.
- [ ] **4.21** `[GREEN]` `[AD-4]` Edit `firestore.rules:637-641` chats `create`: ADD
      `request.resource.data.keys().hasOnly(['chatId','members','createdAt'])`. Keep
      existing `members.size()==2`/`auth.uid in members`/sort/doc-id pins unchanged.
- [ ] **4.22** `[GATE]` Re-run 4.19-4.20 — 4.19 now `assertFails`, 4.20 stays
      `assertSucceeds`.
- [ ] **4.23** `[GATE]` Full `scripts/rules_test/` suite green (all 4 slices, every
      test file) via `scripts/test_rules.sh`. This is the final regression gate before
      PR D deploy — non-vacuity across the entire suite (every deny paired with an allow)
      must hold end to end.
- [ ] **4.24** `[GATE]` `firebase deploy --only firestore:rules,storage:rules --dry-run`
      compiles with no syntax errors.
- [ ] **4.25** `[MANUAL]` User's manual step: run
      `firebase deploy --only firestore:rules,storage:rules` to ship PR D, only after
      4.23 and 4.24 are green and the PR is merged. This is the FINAL deploy of the
      rules-hardening change — all 11 audit findings from Engram obs #405 are now closed
      (10 confirmed findings + the Slice C role-vs-link residual explicitly documented as
      deferred, not dropped, per pre-flight 0.1).

---

## Review Workload Forecast

| Slice | Files touched (rules + tests) | Est. changed lines (rule diff + new test file) | Chained PR |
|---|---|---|---|
| A (Storage) | `storage.rules` (~15 lines changed), `scripts/rules_test/` harness ext. (~10 lines), new `chat-media-storage.test.js` (~90-120 lines), `scripts/test_rules.sh` (1 line) | **~120-145** | PR A |
| B (reviews + trainerPublicProfiles) | `firestore.rules` reviews create (~8 lines) + trainerPublicProfiles create/update (~6 lines), new `reviews-links.test.js` (~130-160 lines) | **~145-175** | PR B |
| C (coach-collections role gate) | `firestore.rules` 5 collections × ~2-4 lines each (~15-20 lines total, incl. the `athlete_billing` combined-block predicate), new `coach-collections.test.js` (~140-170 lines, 4 collections × deny+allow+residual+self-book) | **~155-190** | PR C |
| D (posts/friendships/trainer_links/chats) | `firestore.rules` 4 rule blocks (~35-45 lines total — trainer_links transition OR-clause is the biggest single addition at ~20 lines), 3 new test files (`post-friendship-pins.test.js`, `trainer-links-transitions.test.js` folded or separate, ~250-300 lines combined across posts+friendships+trainer_links+chats scenarios) | **~285-345** | PR D |

**Totals:** ~705-855 changed lines across 4 PRs; **no single PR exceeds ~345 lines**,
each comfortably under a 400-line review budget on its own.

- **Chained PRs recommended: Yes** — already the design's mandated ship order (AD-6),
  four independently reversible, dependency-ordered PRs, Storage first.
- **400-line budget risk: Low** — every individual slice estimate stays under 400 lines
  even at the high end of its range; Slice D is the largest and still ~55 lines of
  headroom at the high estimate. No slice needs further splitting.
- **Decision needed before apply: Yes, but narrow** — not a size/budget decision (risk is
  low), but the two pre-flight spec/design divergences (0.1: Slice C role-vs-link scope;
  coach-link-lifecycle's `'accepted'` vs `'active'` status typo) must be explicitly
  acknowledged by whoever runs `sdd-apply`/reviews the PRs, so the implementation does not
  silently follow the (incorrect) spec text over the (verified-correct) design text.
