/**
 * Firestore security-rules tests for the «Correos promocionales» toggle of
 * Perfil › Privacidad (app), which writes
 * `users/{uid}.notificationPrefs.novedades_plan.email`.
 *
 * Why this file exists: the backend (`emailChannelAllowed`, in
 * `mail/send-queued-mail.ts`) stops commercial mail only when that exact field
 * is an explicit `false`. The app's toggle is the user's way to say so, and the
 * privacy policy promises it ("Revocar consentimiento: desde los ajustes"). If
 * the rules ever stopped letting the owner write that field — say, a future
 * `hasOnly` on the `users` update — the toggle would fail for every user and
 * the failure would be a snackbar nobody files a bug about. No other test pins
 * it.
 *
 * Asserts, with the write SHAPE the app actually sends
 * (`set({notificationPrefs: {novedades_plan: {email: v}}}, {merge: true})`,
 * see `UserRepository.setCorreosPromocionales`):
 *  1. The owner CAN write `false` and `true`, athlete or trainer.
 *  2. The merge does not clobber the rest of `notificationPrefs` (the matrix
 *     the Coach Hub saves) nor the other fields of the document.
 *  3. Another signed-in user CANNOT write someone else's preference, and the
 *     stored value does not move. (This is the one that matters: a hole here
 *     lets anyone opt a stranger out of mail, or back in.)
 *  4. An unauthenticated client cannot write it either.
 *
 * Uses `@firebase/rules-unit-testing` against the Firestore emulator with
 * `firestore.rules` actually loaded and enforced (same pattern as
 * users-subscription-rules.test.ts). Unlike that file, the emulator address is
 * read from `FIRESTORE_EMULATOR_HOST` — `firebase emulators:exec` sets it — so
 * this runs on non-default ports when another session already owns 8080.
 *
 * Run against the Firestore emulator:
 *   firebase emulators:exec --only firestore,auth \
 *     "npm --prefix functions test -- --runInBand correos-promocionales-rules"
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

// `firebase emulators:exec` exports this; the fallback is the default port of
// `firebase.json`, for running the file against an emulator started by hand.
process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";

const PROJECT_ID = "treino-rules-test";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const COL_USERS = "users";
const PREF_KEY = "novedades_plan";

/** `host:port` of the emulator, from the env var `emulators:exec` exports. */
function emulatorAddress(): { host: string; port: number } {
  const raw = process.env.FIRESTORE_EMULATOR_HOST as string;
  const i = raw.lastIndexOf(":");
  return { host: raw.slice(0, i), port: Number(raw.slice(i + 1)) };
}

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  setLogLevel("error");
  const { host, port } = emulatorAddress();
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host,
      port,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

interface UserFixture {
  uid: string;
  role: "athlete" | "trainer";
  email: string;
  createdAt: number;
  displayName?: string;
  notificationPrefs?: Record<string, Record<string, boolean>>;
}

/** Seed a users/{uid} doc via an Admin-privileged context (rules disabled). */
async function seedUser(fixture: UserFixture): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection(COL_USERS).doc(fixture.uid).set(fixture);
  });
}

/** The stored document, read with the rules disabled. */
async function readUser(uid: string): Promise<Record<string, unknown>> {
  let data: Record<string, unknown> | undefined;
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const snap = await ctx.firestore().collection(COL_USERS).doc(uid).get();
    data = snap.data();
  });
  return data as Record<string, unknown>;
}

/** The exact shape `UserRepository.setCorreosPromocionales` writes. */
function appWrite(email: boolean): Record<string, unknown> {
  return { notificationPrefs: { [PREF_KEY]: { email } } };
}

describe("users rules — toggle «Correos promocionales» (notificationPrefs.novedades_plan.email)", () => {
  describe.each(["athlete", "trainer"] as const)("owner (%s)", (role) => {
    const uid = `owner-${role}`;

    const seed = (extra: Partial<UserFixture> = {}) =>
      seedUser({
        uid,
        role,
        email: `${uid}@example.test`,
        createdAt: 0,
        ...extra,
      });

    it("can turn it OFF with the nested map + merge the app sends", async () => {
      await seed();
      const ref = testEnv
        .authenticatedContext(uid)
        .firestore()
        .collection(COL_USERS)
        .doc(uid);

      await assertSucceeds(ref.set(appWrite(false), { merge: true }));

      const stored = await readUser(uid);
      expect(stored.notificationPrefs).toEqual({ [PREF_KEY]: { email: false } });
    });

    it("can turn it back ON", async () => {
      await seed({ notificationPrefs: { [PREF_KEY]: { email: false } } });
      const ref = testEnv
        .authenticatedContext(uid)
        .firestore()
        .collection(COL_USERS)
        .doc(uid);

      await assertSucceeds(ref.set(appWrite(true), { merge: true }));

      const stored = await readUser(uid);
      expect(stored.notificationPrefs).toEqual({ [PREF_KEY]: { email: true } });
    });

    it("merge keeps the Coach Hub matrix, the push channel and every other field", async () => {
      await seed({
        displayName: "Ana",
        notificationPrefs: {
          mensaje_nuevo: { push: true, email: false },
          nueva_solicitud: { push: false, email: true },
          [PREF_KEY]: { push: false },
        },
      });
      const ref = testEnv
        .authenticatedContext(uid)
        .firestore()
        .collection(COL_USERS)
        .doc(uid);

      await assertSucceeds(ref.set(appWrite(false), { merge: true }));

      const stored = await readUser(uid);
      expect(stored).toMatchObject({
        uid,
        role,
        email: `${uid}@example.test`,
        displayName: "Ana",
      });
      expect(stored.notificationPrefs).toEqual({
        mensaje_nuevo: { push: true, email: false },
        nueva_solicitud: { push: false, email: true },
        // Deep merge: `push` survives and `email` is added.
        [PREF_KEY]: { push: false, email: false },
      });
    });

    it("can also write it with a dotted field path through update()", async () => {
      // Not the app's shape, but the other legitimate way to say the same
      // thing; the rules must not care which of the two the client picked.
      await seed({ notificationPrefs: { mensaje_nuevo: { push: true } } });
      const ref = testEnv
        .authenticatedContext(uid)
        .firestore()
        .collection(COL_USERS)
        .doc(uid);

      await assertSucceeds(
        ref.update({ [`notificationPrefs.${PREF_KEY}.email`]: false }),
      );

      const stored = await readUser(uid);
      expect(stored.notificationPrefs).toEqual({
        mensaje_nuevo: { push: true },
        [PREF_KEY]: { email: false },
      });
    });
  });

  describe("somebody else", () => {
    const victim = "victim-athlete";
    const attacker = "attacker-athlete";

    const seedVictim = (extra: Partial<UserFixture> = {}) =>
      seedUser({
        uid: victim,
        role: "athlete",
        email: `${victim}@example.test`,
        createdAt: 0,
        ...extra,
      });

    it("another signed-in user CANNOT turn the victim's mail OFF", async () => {
      await seedVictim();
      const ref = testEnv
        .authenticatedContext(attacker)
        .firestore()
        .collection(COL_USERS)
        .doc(victim);

      await assertFails(ref.set(appWrite(false), { merge: true }));

      const stored = await readUser(victim);
      expect(stored.notificationPrefs).toBeUndefined();
    });

    it("another signed-in user CANNOT turn the victim's mail back ON", async () => {
      // The mirror image, and the nastier one: the victim opted out, and a
      // stranger flips it back so the commercial mail resumes.
      await seedVictim({ notificationPrefs: { [PREF_KEY]: { email: false } } });
      const ref = testEnv
        .authenticatedContext(attacker)
        .firestore()
        .collection(COL_USERS)
        .doc(victim);

      await assertFails(ref.set(appWrite(true), { merge: true }));

      const stored = await readUser(victim);
      expect(stored.notificationPrefs).toEqual({ [PREF_KEY]: { email: false } });
    });

    it("another signed-in user CANNOT even read it", async () => {
      await seedVictim({ notificationPrefs: { [PREF_KEY]: { email: false } } });
      const ref = testEnv
        .authenticatedContext(attacker)
        .firestore()
        .collection(COL_USERS)
        .doc(victim);

      await assertFails(ref.get());
    });

    it("an unauthenticated client CANNOT write it", async () => {
      await seedVictim();
      const ref = testEnv
        .unauthenticatedContext()
        .firestore()
        .collection(COL_USERS)
        .doc(victim);

      await assertFails(ref.set(appWrite(false), { merge: true }));

      const stored = await readUser(victim);
      expect(stored.notificationPrefs).toBeUndefined();
    });
  });
});
