/**
 * Firestore security-rules baseline for the ATHLETE side of a BLOCKED link —
 * paywall Fase 7, the half of the enforcement that must never move.
 *
 * The paywall restricts what a TRAINER may WRITE once their subscription can
 * no longer carry an athlete: the link goes `entitlement: 'blocked'` while
 * `status` stays `'active'`. The product decision behind it is absolute —
 * THE ATHLETE NEVER LOSES ANYTHING. They did not pay, they did not do
 * anything wrong, and their training history is theirs.
 *
 * So this file pins the other side of the contract: with the link blocked,
 * the athlete still READS everything they read before —
 *
 *   trainer_links     the link doc itself (member read)
 *   routines          the plan the trainer assigned them
 *   users/{uid}/sessions          their training sessions
 *   users/{uid}/sessions/setLogs  every set they logged
 *   measurements      their body measurements, trainer-recorded included
 *   chats             the conversation with their coach
 *   chats/messages    every message in it
 *   athlete_billing   what they are being charged
 *   payments          their payment history
 *
 * COVERAGE OF `list` — stated exactly, because `get` and `list` are separate
 * permissions and a rule can pass a doc read while still breaking the
 * athlete's screen on a query. Every collection the athlete's client actually
 * QUERIES is exercised as a query here: trainer_links (`where athleteId`),
 * routines (`where assignedTo`), sessions, setLogs, chats (`where members
 * array-contains`), messages, measurements (`where athleteId`) and payments
 * (`where athleteId`). `routines` is the one that most needs it —
 * firestore.rules:147-148 spells out that its `resource == null` branch
 * applies to `get` only, so get and list diverge there BY DESIGN and a passing
 * `get` says nothing about the query.
 *
 * `chats` carries BOTH shapes, so both are covered. The athlete opens one
 * conversation by id (chat_repository.dart `watchById` → `chats.doc(chatId)`)
 * AND lists all of them: `watchChatsForUser` runs
 * `chats.where('members', arrayContains: uid).orderBy('lastMessageAt')`, and
 * `chatsForCurrentUserProvider` (chat_providers.dart:55-59) feeds it whatever
 * `currentUidProvider` holds — the athlete's uid included. The list is the
 * half that carries the screen: lose it and the athlete's chat tab comes back
 * empty, which reads exactly like "my coach cut me off".
 *
 * `athlete_billing` IS `get`-only here, and that one is not a gap: the athlete
 * side addresses it by document id (billing_repository.dart builds the
 * deterministic `${trainerId}_${athleteId}`; the athlete vantage is
 * `athleteBillingPairProvider`, billing_providers.dart:34-42). The only query
 * over it is the TRAINER's `athlete_billing where trainerId`, which is not
 * this file's subject.
 *
 * NEGATIVE CONTROLS — every collection below is asserted twice: the athlete is
 * ALLOWED, and an unrelated user is DENIED. Without the second half a green
 * cannot tell "the rule lets the athlete through" apart from "rules are not
 * being enforced at all", and since this suite never runs on a dev machine
 * (Java 21+, see below) that green is the ONLY signal anyone ever sees.
 *
 * NON-VACUOUS READS — a `get` on a document that does not exist SUCCEEDS in
 * Firestore: it returns an empty snapshot, so `assertSucceeds` alone passes
 * even if the seed never landed. Every `get` below therefore also asserts
 * `.exists` plus a seeded field, and every `list` asserts the seeded document
 * is really in the result.
 *
 * The same trap runs the other way round on the DENIAL side, and it caught the
 * sessions/setLogs controls: their rule turns an outsider away either because
 * `session_shares/{athleteId}` names somebody else, or because that document
 * is not there AT ALL — and only the first is the rule discriminating. A
 * denial produced by a missing fixture would survive even if the
 * `trainerId == request.auth.uid` comparison were deleted from the rule, so it
 * proves nothing about that comparison.
 * So the seed plants a REAL `session_shares/{ATHLETE}` grant naming the coach,
 * and the outsider is refused by the `trainerId == request.auth.uid`
 * comparison itself.
 *
 * DIVISION OF LABOUR — this file DOCUMENTS the promise, it does not enforce
 * it. Enforcement lives in `rules-read-isolation.test.ts`, a static scanner
 * that fails if ANY read clause ever starts depending on paywall block state,
 * including through a shared helper. The two ship together on purpose: this
 * one explains to a human what must stay true, that one catches the change
 * that would break it. Neither replaces the other.
 *
 * Uses `@firebase/rules-unit-testing` against the Firestore emulator with
 * `firestore.rules` actually loaded and enforced (same pattern as
 * trainer-links-paywall-rules.test.ts).
 *
 * Run against the Firestore emulator:
 *   firebase emulators:exec --only firestore,auth \
 *     "npm --prefix functions run test:rules"
 *
 * Requires Java 21+ for the emulator binary — NOT runnable locally in this
 * environment (Java 17). Runs in CI, which executes the whole suite under
 * `firebase emulators:exec`. Same precedent as
 * trainer-links-paywall-rules.test.ts: do not skip writing a rules test
 * because it cannot run on this machine.
 */

import * as fs from "fs";
import * as path from "path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { setLogLevel } from "firebase/firestore";

const PROJECT_ID = "treino-rules-test";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const TRAINER = "trainer-over-limit";
const ATHLETE = "athlete-blocked-link";
const OTHER_TRAINER = "trainer-someone-else";
const OTHER_ATHLETE = "athlete-someone-else";
/**
 * Authenticated, and related to NOTHING in the seeded world: not a member of
 * the link, not assigned the routine, not in the chat, holder of no share doc.
 * Every negative control runs as this user, so a denial can only come from the
 * rules themselves and never from being unauthenticated.
 */
const OUTSIDER = "user-with-no-relation";

const LINK_ID = "link-blocked-but-active";
const OTHER_LINK_ID = "link-of-someone-else";
const ROUTINE_ID = "routine-assigned-to-athlete";
const OTHER_ROUTINE_ID = "routine-of-someone-else";
const SESSION_ID = "session-of-the-athlete";
const SET_LOG_ID = "setlog-of-the-athlete";
const MEASUREMENT_ID = "measurement-of-the-athlete";
const OTHER_MEASUREMENT_ID = "measurement-of-someone-else";
const MESSAGE_ID = "message-from-the-coach";
const PAYMENT_ID = "payment-of-the-athlete";

// chats/{chatId}: members sorted ascending, id joined with "_" (rules pin both).
const CHAT_MEMBERS = [ATHLETE, TRAINER].sort();
const CHAT_ID = CHAT_MEMBERS.join("_");
// A conversation between two strangers. OJO con por que esta: Firestore evalua
// una regla de `list` contra las RESTRICCIONES DE LA QUERY, no contra los docs
// guardados, asi que este doc NO cambia si la query se permite o se deniega.
// Lo que compra es la asercion del RESULTADO: sin el, el set devuelto seria
// trivialmente correcto porque no hay nada mas que devolver.
const OTHER_CHAT_MEMBERS = [OTHER_ATHLETE, OTHER_TRAINER].sort();
const OTHER_CHAT_ID = OTHER_CHAT_MEMBERS.join("_");
// athlete_billing/{docId}: deterministic `${trainerId}_${athleteId}`.
const BILLING_ID = `${TRAINER}_${ATHLETE}`;

const AT = new Date("2026-08-20T12:00:00.000Z");

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  setLogLevel("error");
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: "127.0.0.1",
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

/**
 * Seeds the whole blocked-link world through an Admin-privileged context
 * (rules disabled). Every assertion below then runs as the ATHLETE with rules
 * enforced — seeding is setup, never evidence.
 */
beforeEach(async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();

    // The link the paywall downgraded: still ACTIVE, entitlement BLOCKED.
    // That combination is the whole point — a blocked link is not a
    // terminated one, the relationship is intact and only the trainer's
    // write surface shrinks.
    await db.collection("trainer_links").doc(LINK_ID).set({
      trainerId: TRAINER,
      athleteId: ATHLETE,
      status: "active",
      entitlement: "blocked",
      blockedAt: AT,
      blockedReason: "nonpayment",
      requestedAt: AT,
      acceptedAt: AT,
      sharedWithTrainer: false,
    });

    await db.collection("routines").doc(ROUTINE_ID).set({
      id: ROUTINE_ID,
      name: "Plan de fuerza - mesociclo 2",
      assignedBy: TRAINER,
      assignedTo: ATHLETE,
      createdBy: TRAINER,
      source: "trainer-assigned",
      // `private` on purpose: the public/shared branches of the routines read
      // rule would let ANY authenticated user through, so a public fixture
      // would prove nothing about the athlete specifically.
      visibility: "private",
      createdAt: AT,
    });

    await db
      .collection("users").doc(ATHLETE)
      .collection("sessions").doc(SESSION_ID)
      .set({
        id: SESSION_ID,
        routineId: ROUTINE_ID,
        startedAt: AT,
        finishedAt: AT,
      });

    await db
      .collection("users").doc(ATHLETE)
      .collection("sessions").doc(SESSION_ID)
      .collection("setLogs").doc(SET_LOG_ID)
      .set({
        id: SET_LOG_ID,
        exerciseId: "back-squat",
        reps: 5,
        weightKg: 100,
        createdAt: AT,
      });

    // The athlete's live session-share grant, pointing at their coach — what
    // syncSessionShareOnTrainerLink maintains ({ trainerId, updatedAt }).
    //
    // It is here FOR THE NEGATIVE CONTROLS. The sessions/setLogs read rule is
    // `owner || (exists(session_shares/{uid}) && get(...).trainerId == uid)`.
    // Without this document the outsider is denied by `exists()` coming back
    // false — a denial the rule would still produce with its trainerId check
    // ripped out. With it, the outsider is denied by the comparison, which is
    // the thing the control claims to be testing.
    //
    // It changes nothing on the athlete's own reads: the owner branch is
    // first and `||` short-circuits before the get() (that ordering is pinned
    // statically in rules-read-isolation.test.ts §7).
    await db.collection("session_shares").doc(ATHLETE).set({
      trainerId: TRAINER,
      updatedAt: AT,
    });

    // Recorded BY the trainer, ABOUT the athlete — the case where "the
    // trainer lost their entitlement" could most plausibly be misread as
    // "the data goes away with them".
    await db.collection("measurements").doc(MEASUREMENT_ID).set({
      id: MEASUREMENT_ID,
      athleteId: ATHLETE,
      recordedBy: TRAINER,
      recordedAt: AT,
      weightKg: 78,
      waistCm: 82,
    });

    await db.collection("chats").doc(CHAT_ID).set({
      members: CHAT_MEMBERS,
      linkId: LINK_ID,
      createdAt: AT,
      lastMessageText: "Nos vemos el martes",
      lastMessageAt: AT,
    });

    await db
      .collection("chats").doc(CHAT_ID)
      .collection("messages").doc(MESSAGE_ID)
      .set({
        senderId: TRAINER,
        text: "Nos vemos el martes",
        createdAt: AT,
      });

    await db.collection("athlete_billing").doc(BILLING_ID).set({
      trainerId: TRAINER,
      athleteId: ATHLETE,
      amountArs: 45000,
      cadence: "mensual",
      updatedAt: AT,
    });

    await db.collection("payments").doc(PAYMENT_ID).set({
      id: PAYMENT_ID,
      trainerId: TRAINER,
      athleteId: ATHLETE,
      amountArs: 45000,
      concept: "Mensualidad agosto",
      status: "pending",
      periodKey: "2026-08",
      createdAt: AT,
      paidAt: null,
      dueAt: AT,
      lastOverdueNotifiedAt: null,
    });

    // ── Noise from an UNRELATED trainer/athlete pair ────────────────────────
    // Que hace y que NO hace, porque es facil creerle de mas: Firestore decide
    // un `list` mirando las RESTRICCIONES DE LA QUERY contra la regla, no los
    // documentos guardados. Estos docs NO cambian si la query se permite o se
    // deniega, y por lo tanto NO fortalecen la mitad de denegacion.
    // Lo que si compran: que las aserciones sobre el RESULTADO sean
    // significativas. Sin ruido, "la query del alumno devuelve exactamente su
    // documento" se cumple trivialmente porque no existe ningun otro.
    await db.collection("payments").doc("payment-of-someone-else").set({
      id: "payment-of-someone-else",
      trainerId: OTHER_TRAINER,
      athleteId: OTHER_ATHLETE,
      amountArs: 1000,
      concept: "Otra cosa",
      status: "pending",
      periodKey: null,
      createdAt: AT,
      paidAt: null,
      dueAt: null,
      lastOverdueNotifiedAt: null,
    });

    await db.collection("trainer_links").doc(OTHER_LINK_ID).set({
      trainerId: OTHER_TRAINER,
      athleteId: OTHER_ATHLETE,
      status: "active",
      entitlement: "active",
      requestedAt: AT,
      acceptedAt: AT,
      sharedWithTrainer: false,
    });

    await db.collection("routines").doc(OTHER_ROUTINE_ID).set({
      id: OTHER_ROUTINE_ID,
      name: "Plan de otro alumno",
      assignedBy: OTHER_TRAINER,
      assignedTo: OTHER_ATHLETE,
      createdBy: OTHER_TRAINER,
      source: "trainer-assigned",
      visibility: "private",
      createdAt: AT,
    });

    await db.collection("measurements").doc(OTHER_MEASUREMENT_ID).set({
      id: OTHER_MEASUREMENT_ID,
      athleteId: OTHER_ATHLETE,
      recordedBy: OTHER_TRAINER,
      recordedAt: AT,
      weightKg: 91,
      waistCm: 95,
    });

    // `lastMessageAt` is not decoration: watchChatsForUser orders by it, and
    // Firestore DROPS documents that lack the ordered field — a noise chat
    // without it would silently stop being noise.
    await db.collection("chats").doc(OTHER_CHAT_ID).set({
      members: OTHER_CHAT_MEMBERS,
      linkId: OTHER_LINK_ID,
      createdAt: AT,
      lastMessageText: "Nada que ver con este alumno",
      lastMessageAt: AT,
    });
  });
});

/** The athlete's own client — rules ENFORCED. */
function athleteDb() {
  return testEnv.authenticatedContext(ATHLETE).firestore();
}

/**
 * An authenticated user related to nothing in the seeded world — rules
 * ENFORCED. Every negative control runs here rather than unauthenticated, so
 * a denial can only come from the read clause itself and never from the
 * `request.auth != null` guard that every rule in the file shares.
 */
function outsiderDb() {
  return testEnv.authenticatedContext(OUTSIDER).firestore();
}

describe("blocked link — the fixture is really blocked", () => {
  // Guard against the worst kind of green: every assertion below would also
  // pass against a perfectly healthy link. This pins that the world under
  // test is the blocked one.
  it("the link is entitlement:blocked and status:active", async () => {
    const snap = await assertSucceeds(
      athleteDb().collection("trainer_links").doc(LINK_ID).get(),
    );
    expect(snap.exists).toBe(true);
    expect(snap.data()?.entitlement).toBe("blocked");
    expect(snap.data()?.status).toBe("active");
  });

  it("lists the link from the athlete side", async () => {
    const list = await assertSucceeds(
      athleteDb()
        .collection("trainer_links")
        .where("athleteId", "==", ATHLETE)
        .get(),
    );
    // Exactly the athlete's link: the unrelated pair seeded alongside it is
    // filtered out by the query, not by the rule.
    expect(list.docs.map((d) => d.id)).toEqual([LINK_ID]);
  });
});

describe("blocked link — the athlete still reads their training", () => {
  it("reads the routine the trainer assigned them", async () => {
    const snap = await assertSucceeds(
      athleteDb().collection("routines").doc(ROUTINE_ID).get(),
    );
    expect(snap.exists).toBe(true);
    expect(snap.data()?.assignedTo).toBe(ATHLETE);
  });

  it("lists the routines assigned to them", async () => {
    // The query the athlete's client actually runs. It matters on its own
    // because firestore.rules:147-148 says the `resource == null` branch of
    // the routines read rule covers `get` only — get and list diverge here BY
    // DESIGN, so the passing `get` above proves nothing about this.
    const list = await assertSucceeds(
      athleteDb()
        .collection("routines")
        .where("assignedTo", "==", ATHLETE)
        .get(),
    );
    expect(list.docs.map((d) => d.id)).toEqual([ROUTINE_ID]);
  });

  it("reads and lists their sessions", async () => {
    const snap = await assertSucceeds(
      athleteDb()
        .collection("users").doc(ATHLETE)
        .collection("sessions").doc(SESSION_ID)
        .get(),
    );
    expect(snap.exists).toBe(true);
    expect(snap.data()?.routineId).toBe(ROUTINE_ID);

    const list = await assertSucceeds(
      athleteDb()
        .collection("users").doc(ATHLETE)
        .collection("sessions")
        .get(),
    );
    expect(list.docs.map((d) => d.id)).toEqual([SESSION_ID]);
  });

  it("reads and lists the set logs inside a session", async () => {
    const snap = await assertSucceeds(
      athleteDb()
        .collection("users").doc(ATHLETE)
        .collection("sessions").doc(SESSION_ID)
        .collection("setLogs").doc(SET_LOG_ID)
        .get(),
    );
    expect(snap.exists).toBe(true);
    expect(snap.data()?.weightKg).toBe(100);

    const list = await assertSucceeds(
      athleteDb()
        .collection("users").doc(ATHLETE)
        .collection("sessions").doc(SESSION_ID)
        .collection("setLogs")
        .get(),
    );
    expect(list.docs.map((d) => d.id)).toEqual([SET_LOG_ID]);
  });

  it("reads and lists their measurements, including trainer-recorded ones", async () => {
    const snap = await assertSucceeds(
      athleteDb().collection("measurements").doc(MEASUREMENT_ID).get(),
    );
    expect(snap.exists).toBe(true);
    expect(snap.data()?.recordedBy).toBe(TRAINER);

    const list = await assertSucceeds(
      athleteDb()
        .collection("measurements")
        .where("athleteId", "==", ATHLETE)
        .get(),
    );
    expect(list.docs.map((d) => d.id)).toEqual([MEASUREMENT_ID]);
  });
});

describe("blocked link — the athlete still reads the conversation", () => {
  it("reads the chat with their coach", async () => {
    const snap = await assertSucceeds(
      athleteDb().collection("chats").doc(CHAT_ID).get(),
    );
    expect(snap.exists).toBe(true);
    expect(snap.data()?.linkId).toBe(LINK_ID);
  });

  it("lists the chats they are a member of", async () => {
    // The query the athlete's client actually runs (chat_repository.dart
    // watchChatsForUser), orderBy included. The `get` above proves nothing
    // about it: `list` evaluates the read rule against every candidate
    // document, and the collection also holds a conversation between two
    // strangers. This is the read that populates the chat tab — the surface
    // where "the athlete lost their coach" would be most visible.
    const list = await assertSucceeds(
      athleteDb()
        .collection("chats")
        .where("members", "array-contains", ATHLETE)
        .orderBy("lastMessageAt", "desc")
        .get(),
    );
    expect(list.docs.map((d) => d.id)).toEqual([CHAT_ID]);
  });

  it("reads and lists the messages of that chat", async () => {
    const snap = await assertSucceeds(
      athleteDb()
        .collection("chats").doc(CHAT_ID)
        .collection("messages").doc(MESSAGE_ID)
        .get(),
    );
    expect(snap.exists).toBe(true);
    expect(snap.data()?.senderId).toBe(TRAINER);

    const list = await assertSucceeds(
      athleteDb()
        .collection("chats").doc(CHAT_ID)
        .collection("messages")
        .get(),
    );
    expect(list.docs.map((d) => d.id)).toEqual([MESSAGE_ID]);
  });
});

describe("blocked link — the athlete still reads their money", () => {
  it("reads the billing config their trainer set for them", async () => {
    const snap = await assertSucceeds(
      athleteDb().collection("athlete_billing").doc(BILLING_ID).get(),
    );
    expect(snap.exists).toBe(true);
    expect(snap.data()?.amountArs).toBe(45000);
  });

  it("reads and lists their own payments", async () => {
    const snap = await assertSucceeds(
      athleteDb().collection("payments").doc(PAYMENT_ID).get(),
    );
    expect(snap.exists).toBe(true);
    expect(snap.data()?.concept).toBe("Mensualidad agosto");

    const list = await assertSucceeds(
      athleteDb()
        .collection("payments")
        .where("athleteId", "==", ATHLETE)
        .get(),
    );
    expect(list.docs.map((d) => d.id)).toEqual([PAYMENT_ID]);
  });
});

// ---------------------------------------------------------------------------
// NEGATIVE CONTROLS — what makes the green above mean anything.
// ---------------------------------------------------------------------------
// Everything above is `assertSucceeds`. On its own that is compatible with two
// very different worlds: one where the read clauses correctly let the athlete
// through, and one where firestore.rules never loaded and the emulator is
// allowing everything. This suite cannot run on a dev machine (Java 21+), so
// the CI green is the only evidence anybody ever sees of which world we are
// in — and a suite that can only go green is not evidence.
//
// So every collection covered above is also asserted DENIED for a user with no
// relationship to any of it. A green now says both halves: the rules are being
// enforced, AND the athlete of a blocked link passes them.

describe("negative controls — an unrelated user is denied on every covered collection", () => {
  it("cannot read or list the link", async () => {
    await assertFails(
      outsiderDb().collection("trainer_links").doc(LINK_ID).get(),
    );
    await assertFails(
      outsiderDb()
        .collection("trainer_links")
        .where("athleteId", "==", ATHLETE)
        .get(),
    );
  });

  it("cannot read or list the athlete's routine", async () => {
    await assertFails(
      outsiderDb().collection("routines").doc(ROUTINE_ID).get(),
    );
    await assertFails(
      outsiderDb()
        .collection("routines")
        .where("assignedTo", "==", ATHLETE)
        .get(),
    );
  });

  it("cannot read or list the athlete's sessions", async () => {
    // `session_shares/{ATHLETE}` EXISTS and names the coach, so the trainer
    // branch runs all the way to `get(...).data.trainerId == request.auth.uid`
    // and comes back false on the comparison. The denial is the rule
    // discriminating, not `exists()` tripping over an absent document.
    await assertFails(
      outsiderDb()
        .collection("users").doc(ATHLETE)
        .collection("sessions").doc(SESSION_ID)
        .get(),
    );
    await assertFails(
      outsiderDb()
        .collection("users").doc(ATHLETE)
        .collection("sessions")
        .get(),
    );
  });

  it("cannot read or list the athlete's set logs", async () => {
    // Same shape as sessions above, and the same reason it is not vacuous:
    // the share doc is seeded, so the outsider loses on the trainerId compare.
    await assertFails(
      outsiderDb()
        .collection("users").doc(ATHLETE)
        .collection("sessions").doc(SESSION_ID)
        .collection("setLogs").doc(SET_LOG_ID)
        .get(),
    );
    await assertFails(
      outsiderDb()
        .collection("users").doc(ATHLETE)
        .collection("sessions").doc(SESSION_ID)
        .collection("setLogs")
        .get(),
    );
  });

  it("cannot read or list the athlete's measurements", async () => {
    await assertFails(
      outsiderDb().collection("measurements").doc(MEASUREMENT_ID).get(),
    );
    await assertFails(
      outsiderDb()
        .collection("measurements")
        .where("athleteId", "==", ATHLETE)
        .get(),
    );
  });

  it("cannot read the chat, list the athlete's chats, or list its messages", async () => {
    await assertFails(
      outsiderDb().collection("chats").doc(CHAT_ID).get(),
    );
    // The list half, aimed at the athlete's chats. Querying for the
    // OUTSIDER's own would come back empty-and-allowed, which proves nothing.
    await assertFails(
      outsiderDb()
        .collection("chats")
        .where("members", "array-contains", ATHLETE)
        .orderBy("lastMessageAt", "desc")
        .get(),
    );
    await assertFails(
      outsiderDb()
        .collection("chats").doc(CHAT_ID)
        .collection("messages").doc(MESSAGE_ID)
        .get(),
    );
    await assertFails(
      outsiderDb()
        .collection("chats").doc(CHAT_ID)
        .collection("messages")
        .get(),
    );
  });

  it("cannot read the billing config", async () => {
    await assertFails(
      outsiderDb().collection("athlete_billing").doc(BILLING_ID).get(),
    );
  });

  it("cannot read or list the athlete's payments", async () => {
    await assertFails(
      outsiderDb().collection("payments").doc(PAYMENT_ID).get(),
    );
    await assertFails(
      outsiderDb()
        .collection("payments")
        .where("athleteId", "==", ATHLETE)
        .get(),
    );
  });
});
