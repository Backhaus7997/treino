/**
 * Real Firestore security-rules enforcement tests for `userPublicProfiles/{uid}`.
 *
 * Unlike `ranking-aggregate.test.ts` (which uses the Admin SDK and therefore
 * BYPASSES rule evaluation entirely), this suite uses
 * `@firebase/rules-unit-testing` to open CLIENT-authenticated contexts
 * against the Firestore emulator with `firestore.rules` actually loaded and
 * enforced. This is the missing piece flagged by
 * `openspec/changes/rankings-integrity/verify-report.md` ("THE KEY QUESTION"
 * section): there was previously no executable proof that a forged client
 * write is denied — only manual rule-logic tracing.
 *
 * Run against the Firestore emulator:
 *   firebase emulators:exec --only firestore,auth \
 *     "npm --prefix functions run test:rules"
 *
 * Requires Java (for the emulator binary) — Java 21 via `openjdk@21` is
 * known to work in this environment.
 *
 * REQ traceability: spec `user-public-profiles-layer` — Firestore Rules:
 * Field Allowlist, Owner-Only and UID Immutability, gymId Integrity,
 * CF-Write-Only Ranking Metrics, Type and Range Validation, Read Access
 * Unchanged. rankings-integrity Phase 2 (PR#2) addendum. AD-3, AD-4, AD-6, AD-8.
 */

import * as fs from "fs";
import * as path from "path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  deleteField,
  doc,
  serverTimestamp,
  setDoc,
  setLogLevel,
  updateDoc,
} from "firebase/firestore";

const PROJECT_ID = "treino-rules-test";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const COL_USERS = "users";
const COL_PROFILES = "userPublicProfiles";

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

/** Seed documents via an Admin-privileged context (rules disabled). */
async function seed(
  uid: string,
  opts: {
    userGymId?: string;
    profile?: Record<string, unknown>;
  },
): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    if (opts.userGymId !== undefined) {
      await db
        .collection(COL_USERS)
        .doc(uid)
        .set(
          {
            uid,
            role: "athlete",
            email: `${uid}@example.test`,
            createdAt: 0,
            gymId: opts.userGymId,
          },
          { merge: true },
        );
    }
    if (opts.profile) {
      await db
        .collection(COL_PROFILES)
        .doc(uid)
        .set({ uid, ...opts.profile }, { merge: true });
    }
  });
}

// ---------------------------------------------------------------------------
// 1. Forged ranking metric — the headline security assertion.
// ---------------------------------------------------------------------------
describe("userPublicProfiles rules — CF-write-only ranking metrics", () => {
  const uid = "athlete-forge-metric";

  it("denies an authenticated owner writing a forged metric to their own doc", async () => {
    await seed(uid, {
      userGymId: "gym-a",
      profile: { rankingOptIn: true, bestSquatKg: 100 },
    });

    const alice = testEnv.authenticatedContext(uid);
    const ref = alice.firestore().collection(COL_PROFILES).doc(uid);

    await assertFails(ref.update({ bestSquatKg: 999 }));
  });

  it("allows re-asserting the currently stored metric value (not a forgery)", async () => {
    await seed(uid, {
      userGymId: "gym-a",
      profile: { rankingOptIn: true, lifetimeVolumeKg: 3400 },
    });

    const alice = testEnv.authenticatedContext(uid);
    const ref = alice.firestore().collection(COL_PROFILES).doc(uid);

    await assertSucceeds(
      ref.update({ lifetimeVolumeKg: 3400, displayName: "Alice" }),
    );
  });

  it("allows the Admin SDK (server trigger path) to write a real metric value", async () => {
    await seed(uid, {
      userGymId: "gym-a",
      profile: { rankingOptIn: true, bestSquatKg: 100 },
    });

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await assertSucceeds(
        ctx
          .firestore()
          .collection(COL_PROFILES)
          .doc(uid)
          .update({ bestSquatKg: 110 }),
      );
    });
  });
});

// ---------------------------------------------------------------------------
// 2. Forged gymId — the second headline security assertion.
// ---------------------------------------------------------------------------
describe("userPublicProfiles rules — gymId integrity (getAfter pin)", () => {
  const uid = "athlete-forge-gym";

  it("denies self-assigning to a gym the athlete doesn't attend", async () => {
    await seed(uid, { userGymId: "gym-a", profile: {} });

    const alice = testEnv.authenticatedContext(uid);
    const ref = alice.firestore().collection(COL_PROFILES).doc(uid);

    // Standalone write to the PUBLIC doc only — users/{uid}.gymId stays
    // "gym-a", so getAfter() sees a mismatch against the forged "gym-b".
    await assertFails(ref.update({ gymId: "gym-b" }));
  });

  it("allows a legit simultaneous gym change (batched dual-write, matching gymId)", async () => {
    await seed(uid, { userGymId: "gym-a", profile: {} });

    const alice = testEnv.authenticatedContext(uid);
    const db = alice.firestore();
    const batch = db.batch();
    batch.set(
      db.collection(COL_USERS).doc(uid),
      {
        uid,
        role: "athlete",
        email: `${uid}@example.test`,
        createdAt: 0,
        gymId: "gym-b",
      },
      { merge: true },
    );
    batch.set(
      db.collection(COL_PROFILES).doc(uid),
      { uid, gymId: "gym-b" },
      { merge: true },
    );

    // This is the exact same-WriteBatch shape as UserRepository.update.
    // getAfter() must see the POST-batch users/{uid}.gymId ("gym-b"), not
    // the pre-batch value — proving the getAfter() deviation from a naive
    // get() pin is load-bearing and does not break the real production flow.
    await assertSucceeds(batch.commit());
  });
});

// ---------------------------------------------------------------------------
// 3. Field allowlist.
// ---------------------------------------------------------------------------
describe("userPublicProfiles rules — field allowlist", () => {
  const uid = "athlete-forge-field";

  it("denies a write containing a field outside the field allowlist", async () => {
    await seed(uid, { userGymId: "gym-a", profile: {} });

    const alice = testEnv.authenticatedContext(uid);
    const ref = alice.firestore().collection(COL_PROFILES).doc(uid);

    await assertFails(ref.set({ uid, isAdmin: true }, { merge: true }));
  });
});

// ---------------------------------------------------------------------------
// 4. Disable-transition exception vs. forged-metric-under-disable.
// ---------------------------------------------------------------------------
describe("userPublicProfiles rules — disable-transition exception", () => {
  const uid = "athlete-disable";

  it("allows clearRankingMetrics's exact payload (optIn true->false + metrics->0/null)", async () => {
    await seed(uid, {
      userGymId: "gym-a",
      profile: {
        rankingOptIn: true,
        lifetimeVolumeKg: 3400,
        bestSquatKg: 110,
        bestBenchKg: 80,
        bestDeadliftKg: 150,
      },
    });

    const alice = testEnv.authenticatedContext(uid);
    const ref = alice.firestore().collection(COL_PROFILES).doc(uid);

    await assertSucceeds(
      ref.update({
        rankingOptIn: false,
        lifetimeVolumeKg: 0,
        bestSquatKg: null,
        bestBenchKg: null,
        bestDeadliftKg: null,
      }),
    );
  });

  it("denies flipping optIn to false while forging a non-zero metric (no laundering path)", async () => {
    await seed(uid, {
      userGymId: "gym-a",
      profile: { rankingOptIn: true, bestSquatKg: 110 },
    });

    const alice = testEnv.authenticatedContext(uid);
    const ref = alice.firestore().collection(COL_PROFILES).doc(uid);

    await assertFails(
      ref.update({ rankingOptIn: false, bestSquatKg: 999 }),
    );
  });
});

// ---------------------------------------------------------------------------
// 5. Owner-only.
// ---------------------------------------------------------------------------
describe("userPublicProfiles rules — owner-only", () => {
  it("denies a non-owner writing another user's doc", async () => {
    const victim = "athlete-victim";
    await seed(victim, { userGymId: "gym-a", profile: {} });

    const attacker = testEnv.authenticatedContext("athlete-attacker");
    const ref = attacker.firestore().collection(COL_PROFILES).doc(victim);

    await assertFails(ref.update({ displayName: "pwned" }));
  });
});

// ---------------------------------------------------------------------------
// 6. isProfilePublic privacy flag.
//
// The privacy feature (Instagram-style public/private profiles) writes this
// flag from the client via UserPublicProfileRepository.setProfilePublic —
// a SetOptions(merge: true) partial write. With merge semantics
// request.resource.data is the full POST-merge document, so the field must
// be in the hasOnly allowlist twice over: (a) for the flip itself, and (b)
// so a doc that already stores the flag doesn't fail the allowlist on every
// LATER unrelated merge (updateCounters after each workout, dual-writes...).
// ---------------------------------------------------------------------------
describe("userPublicProfiles rules — isProfilePublic privacy flag", () => {
  const uid = "athlete-privacy";

  it("allows the owner to flip isProfilePublic (setProfilePublic merge shape)", async () => {
    await seed(uid, { userGymId: "gym-a", profile: { displayName: "Alice" } });

    const alice = testEnv.authenticatedContext(uid);
    const ref = alice.firestore().collection(COL_PROFILES).doc(uid);

    // Exact payload + SetOptions(merge: true) shape of
    // UserPublicProfileRepository.setProfilePublic.
    await assertSucceeds(ref.set({ isProfilePublic: false }, { merge: true }));
  });

  it("allows unrelated counter merges on a doc that already stores isProfilePublic", async () => {
    // Doc already carrying the flag (flipped earlier, or backfilled by the
    // Admin SDK). The stored field is part of the post-merge doc on EVERY
    // subsequent merge, so it must not brick unrelated counter writes.
    await seed(uid, {
      userGymId: "gym-a",
      profile: { isProfilePublic: false, followersCount: 3 },
    });

    const alice = testEnv.authenticatedContext(uid);
    const ref = alice.firestore().collection(COL_PROFILES).doc(uid);

    // updateCounters shape of SessionRepository.finish — a real prod merge
    // with no other paired field. (Era `followersCount: 4`, el shape de
    // FriendshipRepository.accept, retirado en PR3d: desde #1835 ese
    // contador es CF-only.)
    await assertSucceeds(ref.set({ workoutsCount: 4 }, { merge: true }));
  });

  it("allows a first-ever write (create) carrying isProfilePublic", async () => {
    // UserPublicProfileRepository.set(profile) serializes the full model,
    // whose freezed default (@Default(true)) always emits the field — so
    // the CREATE branch must accept it too (payload kept minimal; each
    // create constraint is AND'd independently).
    const fresh = "athlete-privacy-create";
    await seed(fresh, { userGymId: "gym-a" });

    const bob = testEnv.authenticatedContext(fresh);
    const ref = bob.firestore().collection(COL_PROFILES).doc(fresh);

    await assertSucceeds(
      ref.set(
        { uid: fresh, displayName: "Bob", isProfilePublic: true },
        { merge: true },
      ),
    );
  });

  it("denies a non-bool isProfilePublic (update branch)", async () => {
    await seed(uid, { userGymId: "gym-a", profile: {} });

    const alice = testEnv.authenticatedContext(uid);
    const ref = alice.firestore().collection(COL_PROFILES).doc(uid);

    await assertFails(ref.set({ isProfilePublic: "yes" }, { merge: true }));
  });

  it("denies a non-bool isProfilePublic (create branch — duplicated guard)", async () => {
    // No profile doc seeded → this merge is a CREATE. The bool guard lives
    // textually duplicated in both branches (see the COUPLING WARNING in
    // firestore.rules) — pin each copy independently.
    const fresh = "athlete-privacy-create-nonbool";
    await seed(fresh, { userGymId: "gym-a" });

    const bob = testEnv.authenticatedContext(fresh);
    const ref = bob.firestore().collection(COL_PROFILES).doc(fresh);

    await assertFails(
      ref.set({ uid: fresh, isProfilePublic: "yes" }, { merge: true }),
    );
  });
});

// ---------------------------------------------------------------------------
// 7. Rangos de levantamiento — squatRank / benchRank / deadliftRank.
//
// Los escribe SÓLO la CF (Admin SDK, saltea las reglas) a partir de best*Kg y
// del peso corporal del doc privado. Reciben el mismo trato que las métricas
// de la sección 1: CF-write-only, con la excepción de la transición de
// opt-out. Y, como `request.resource.data` es el doc mergeado, tienen que
// estar en el `hasOnly` de update: sin eso, un doc que YA tiene un rango
// escrito por la CF no se podría volver a editar nunca (el segundo test).
// ---------------------------------------------------------------------------
describe("userPublicProfiles rules — lift ranks (CF-write-only)", () => {
  const uid = "athlete-ranks";

  it("denies the owner forging a rank on their own doc", async () => {
    await seed(uid, {
      userGymId: "gym-a",
      profile: { rankingOptIn: true, benchRank: 2 },
    });

    const alice = testEnv.authenticatedContext(uid);
    const ref = alice.firestore().collection(COL_PROFILES).doc(uid);

    await assertFails(ref.update({ benchRank: 8 }));
  });

  it("denies the owner seeding a rank the CF never wrote", async () => {
    await seed(uid, { userGymId: "gym-a", profile: { rankingOptIn: true } });

    const alice = testEnv.authenticatedContext(uid);
    const ref = alice.firestore().collection(COL_PROFILES).doc(uid);

    await assertFails(ref.update({ squatRank: 8 }));
  });

  it("keeps a doc that already stores CF-written ranks editable (hasOnly allowlist)", async () => {
    await seed(uid, {
      userGymId: "gym-a",
      profile: {
        rankingOptIn: true,
        squatRank: 5,
        benchRank: 4,
        deadliftRank: 3,
      },
    });

    const alice = testEnv.authenticatedContext(uid);
    const ref = alice.firestore().collection(COL_PROFILES).doc(uid);

    // Un cambio de displayName no toca los rangos, pero el doc mergeado los
    // trae: sin el hasOnly actualizado esto sería permission-denied.
    await assertSucceeds(ref.update({ displayName: "Alice" }));
    // Y re-presentar el valor guardado tampoco es una falsificación.
    await assertSucceeds(ref.update({ benchRank: 4, displayName: "Alicia" }));
  });

  it("allows the Admin SDK (server trigger path) to write a real rank", async () => {
    await seed(uid, {
      userGymId: "gym-a",
      profile: { rankingOptIn: true, benchRank: 2 },
    });

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await assertSucceeds(
        ctx.firestore().collection(COL_PROFILES).doc(uid).update({ benchRank: 6 }),
      );
    });
  });

  it("denies a create that seeds a rank, but accepts one that leaves it null", async () => {
    const fresh = "athlete-ranks-create";
    await seed(fresh, { userGymId: "gym-a" });

    const bob = testEnv.authenticatedContext(fresh);
    const ref = bob.firestore().collection(COL_PROFILES).doc(fresh);

    await assertFails(ref.set({ uid: fresh, benchRank: 8 }));
    await assertSucceeds(
      ref.set({
        uid: fresh,
        benchRank: null,
        squatRank: null,
        deadliftRank: null,
      }),
    );
  });

  it("allows the opt-out transition to reset the ranks to null (clearRankingMetrics)", async () => {
    await seed(uid, {
      userGymId: "gym-a",
      profile: {
        rankingOptIn: true,
        lifetimeVolumeKg: 3400,
        bestSquatKg: 110,
        squatRank: 5,
        benchRank: 4,
        deadliftRank: 3,
      },
    });

    const alice = testEnv.authenticatedContext(uid);
    const ref = alice.firestore().collection(COL_PROFILES).doc(uid);

    await assertSucceeds(
      ref.update({
        rankingOptIn: false,
        lifetimeVolumeKg: 0,
        bestSquatKg: null,
        bestBenchKg: null,
        bestDeadliftKg: null,
        squatRank: null,
        benchRank: null,
        deadliftRank: null,
      }),
    );
  });

  it("denies flipping opt-in off while forging a non-null rank (no laundering path)", async () => {
    await seed(uid, {
      userGymId: "gym-a",
      profile: { rankingOptIn: true, benchRank: 2 },
    });

    const alice = testEnv.authenticatedContext(uid);
    const ref = alice.firestore().collection(COL_PROFILES).doc(uid);

    await assertFails(ref.update({ rankingOptIn: false, benchRank: 8 }));
  });

  it("denies a non-owner writing a rank on someone else's doc", async () => {
    await seed(uid, {
      userGymId: "gym-a",
      profile: { rankingOptIn: true, benchRank: 2 },
    });

    const attacker = testEnv.authenticatedContext("athlete-ranks-attacker");
    const ref = attacker.firestore().collection(COL_PROFILES).doc(uid);

    await assertFails(ref.update({ benchRank: 8 }));
  });
});

// ---------------------------------------------------------------------------
// 8. rachaSemanas — acotada, no forjable (#1698).
//
// `rachaSemanas` ordena el ranking de racha del gym y la escribe el CLIENTE
// (SessionRepository.finish → updateCounters, un set(merge) con el valor y el
// sello `rachaSemanasUpdatedAt: serverTimestamp()`). No hay CF que la derive,
// así que la regla no puede hacerla "sólo del servidor": la ACOTA. Lo que el
// dueño puede dejar escrito es, como mucho, lo que una racha honesta pudo
// alcanzar desde el último sello: el valor guardado + una semana por cada
// semana ART transcurrida (una sola si nunca hubo sello). Bajar es libre. El
// sello sólo puede ser el del servidor (`request.time`) o el que ya estaba.
//
// Las semanas son lunes–domingo en ART (UTC-3 fijo), igual que el cliente
// (`mondayOfWeekArt`) y que `weekly-streak.ts`.
// ---------------------------------------------------------------------------
describe("userPublicProfiles rules — rachaSemanas acotada (#1698)", () => {
  const uid = "athlete-racha";
  const WEEK_MS = 7 * 24 * 60 * 60 * 1000;
  const DAY_MS = 24 * 60 * 60 * 1000;
  // Lunes 1970-01-05 00:00 ART (= 03:00Z), en ms desde epoch. Es el mismo
  // ancla que usa `artWeekIndex` en firestore.rules.
  const MONDAY_ANCHOR_MS = 356400000;

  /** Lunes 00:00 ART de la semana que contiene `ms`. */
  function mondayArt(ms: number): number {
    return (
      Math.floor((ms - MONDAY_ANCHOR_MS) / WEEK_MS) * WEEK_MS + MONDAY_ANCHOR_MS
    );
  }

  /** Un instante a mitad de la semana ART que está `weeks` semanas atrás. */
  function weeksAgo(weeks: number): Date {
    return new Date(mondayArt(Date.now()) - weeks * WEEK_MS + 3 * DAY_MS);
  }

  function profileRef(as: string, target = uid) {
    return doc(
      testEnv.authenticatedContext(as).firestore(),
      COL_PROFILES,
      target,
    );
  }

  async function seedRacha(racha: Record<string, unknown>): Promise<void> {
    await seed(uid, {
      userGymId: "gym-a",
      profile: { displayName: "Alice", ...racha },
    });
  }

  // El payload exacto de UserPublicProfileRepository.updateCounters: un
  // set(merge:true) con el contador, la racha y el sello del servidor.
  function finishWrite(racha: number) {
    return {
      workoutsCount: 20,
      rachaSemanas: racha,
      rachaSemanasUpdatedAt: serverTimestamp(),
    };
  }

  describe("DENY — lo que el dueño no puede forjar", () => {
    it("un valor inventado sobre una racha real (el hallazgo: 9999)", async () => {
      await seedRacha({ rachaSemanas: 3, rachaSemanasUpdatedAt: weeksAgo(1) });
      await assertFails(
        setDoc(profileRef(uid), finishWrite(9999), { merge: true }),
      );
      await assertFails(updateDoc(profileRef(uid), { rachaSemanas: 9999 }));
    });

    it("sembrar una racha en un doc que nunca la tuvo", async () => {
      await seedRacha({});
      await assertFails(updateDoc(profileRef(uid), { rachaSemanas: 50 }));
    });

    it("subir más de +1 cuando el último sello es de la semana pasada", async () => {
      await seedRacha({ rachaSemanas: 3, rachaSemanasUpdatedAt: weeksAgo(1) });
      await assertFails(
        setDoc(profileRef(uid), finishWrite(5), { merge: true }),
      );
    });

    it("subir dentro de la semana del último sello (ya se contó esta semana)", async () => {
      await seedRacha({ rachaSemanas: 3, rachaSemanasUpdatedAt: weeksAgo(0) });
      await assertFails(
        setDoc(profileRef(uid), finishWrite(4), { merge: true }),
      );
    });

    it("subir sin estampar el sello del servidor (reusaría el cupo en cada escritura)", async () => {
      await seedRacha({ rachaSemanas: 3, rachaSemanasUpdatedAt: weeksAgo(1) });
      await assertFails(updateDoc(profileRef(uid), { rachaSemanas: 4 }));
    });

    it("un sello inventado: en el futuro, en el pasado, o sacado", async () => {
      await seedRacha({ rachaSemanas: 3, rachaSemanasUpdatedAt: weeksAgo(1) });
      await assertFails(
        updateDoc(profileRef(uid), {
          rachaSemanas: 4,
          rachaSemanasUpdatedAt: new Date(Date.now() + 52 * WEEK_MS),
        }),
      );
      // Un sello viejo reabriría el cupo semanal.
      await assertFails(
        updateDoc(profileRef(uid), {
          rachaSemanas: 4,
          rachaSemanasUpdatedAt: weeksAgo(8),
        }),
      );
      // Sacarlo haría que el próximo +1 se evalúe como "nunca hubo sello".
      await assertFails(
        updateDoc(profileRef(uid), { rachaSemanasUpdatedAt: deleteField() }),
      );
    });

    it("el sello del servidor y nada más, aunque el valor no cambie", async () => {
      await seedRacha({ rachaSemanas: 3, rachaSemanasUpdatedAt: weeksAgo(1) });
      await assertFails(
        updateDoc(profileRef(uid), {
          rachaSemanasUpdatedAt: new Date(Date.now() + 10 * WEEK_MS),
        }),
      );
    });

    it("valores que no son un entero >= 0", async () => {
      await seedRacha({ rachaSemanas: 3, rachaSemanasUpdatedAt: weeksAgo(1) });
      await assertFails(
        setDoc(profileRef(uid), finishWrite(3.5), { merge: true }),
      );
      await assertFails(
        setDoc(profileRef(uid), finishWrite(-1), { merge: true }),
      );
      await assertFails(updateDoc(profileRef(uid), { rachaSemanas: "4" }));
      await assertFails(updateDoc(profileRef(uid), { rachaSemanas: null }));
    });

    it("una racha vieja no admite más que el cupo de las semanas que pasaron", async () => {
      // Sello de hace 3 semanas → como mucho +3; +4 ya es inventado.
      await seedRacha({ rachaSemanas: 5, rachaSemanasUpdatedAt: weeksAgo(3) });
      await assertFails(
        setDoc(profileRef(uid), finishWrite(9), { merge: true }),
      );
    });

    it("un tercero no escribe la racha de otro", async () => {
      await seedRacha({ rachaSemanas: 3, rachaSemanasUpdatedAt: weeksAgo(1) });
      await assertFails(
        setDoc(profileRef("athlete-racha-attacker"), finishWrite(4), {
          merge: true,
        }),
      );
    });

    it("un create no puede sembrar una racha ni un sello inventado", async () => {
      const fresh = "athlete-racha-create";
      await seed(fresh, { userGymId: "gym-a" });
      const ref = profileRef(fresh, fresh);
      await assertFails(setDoc(ref, { uid: fresh, rachaSemanas: 40 }));
      await assertFails(
        setDoc(ref, {
          uid: fresh,
          rachaSemanas: 0,
          rachaSemanasUpdatedAt: new Date(Date.now() + 52 * WEEK_MS),
        }),
      );
    });
  });

  describe("ALLOW — el flujo real de SessionRepository.finish", () => {
    it("la semana siguiente suma +1 con el sello del servidor (racha que continúa)", async () => {
      await seedRacha({ rachaSemanas: 3, rachaSemanasUpdatedAt: weeksAgo(1) });
      await assertSucceeds(
        setDoc(profileRef(uid), finishWrite(4), { merge: true }),
      );
    });

    it("la primera racha de un doc sembrado en 0 sin sello (seed_racha_semanas.js)", async () => {
      await seedRacha({ rachaSemanas: 0 });
      await assertSucceeds(
        setDoc(profileRef(uid), finishWrite(1), { merge: true }),
      );
    });

    it("otra sesión la misma semana: mismo valor, sello renovado", async () => {
      await seedRacha({ rachaSemanas: 3, rachaSemanasUpdatedAt: weeksAgo(0) });
      await assertSucceeds(
        setDoc(profileRef(uid), finishWrite(3), { merge: true }),
      );
    });

    it("racha cortada: baja a 1 (o a 0) sin límite", async () => {
      await seedRacha({ rachaSemanas: 7, rachaSemanasUpdatedAt: weeksAgo(4) });
      await assertSucceeds(
        setDoc(profileRef(uid), finishWrite(1), { merge: true }),
      );
      await assertSucceeds(
        setDoc(profileRef(uid), finishWrite(0), { merge: true }),
      );
    });

    it("escrituras perdidas: el cupo es de una semana por semana transcurrida", async () => {
      // Se perdió el write de las últimas semanas (app matada antes del ACK,
      // sesiones del reloj): el próximo finish recalcula +3 de una vez.
      await seedRacha({ rachaSemanas: 5, rachaSemanasUpdatedAt: weeksAgo(3) });
      await assertSucceeds(
        setDoc(profileRef(uid), finishWrite(8), { merge: true }),
      );
    });

    it("el borde de semana es el lunes 00:00 ART, al milisegundo", async () => {
      const lunes = mondayArt(Date.now());
      // Sello EXACTO en el lunes de esta semana → misma semana: no sube.
      await seedRacha({
        rachaSemanas: 3,
        rachaSemanasUpdatedAt: new Date(lunes),
      });
      await assertFails(
        setDoc(profileRef(uid), finishWrite(4), { merge: true }),
      );
      // Un milisegundo antes → semana pasada: sube.
      await seedRacha({
        rachaSemanas: 3,
        rachaSemanasUpdatedAt: new Date(lunes - 1),
      });
      await assertSucceeds(
        setDoc(profileRef(uid), finishWrite(4), { merge: true }),
      );
    });

    it("un doc con una racha legacy ya inflada sigue editable (sin congelación, #849)", async () => {
      // El valor guardado no se puede forjar de nuevo, pero tampoco hay que
      // inmovilizar al dueño que lo arrastra: re-presentarlo es `unchanged`.
      await seedRacha({ rachaSemanas: 99, rachaSemanasUpdatedAt: weeksAgo(0) });
      await assertSucceeds(
        updateDoc(profileRef(uid), { displayName: "Alicia" }),
      );
      await assertSucceeds(updateDoc(profileRef(uid), { rachaSemanas: 99 }));
    });

    it("un create con la racha en 0 (o null) sigue pasando", async () => {
      const fresh = "athlete-racha-create-ok";
      await seed(fresh, { userGymId: "gym-a" });
      await assertSucceeds(
        setDoc(profileRef(fresh, fresh), { uid: fresh, rachaSemanas: 0 }),
      );
      const fresh2 = "athlete-racha-create-null";
      await seed(fresh2, { userGymId: "gym-a" });
      await assertSucceeds(
        setDoc(profileRef(fresh2, fresh2), {
          uid: fresh2,
          rachaSemanas: null,
        }),
      );
    });

    it("el Admin SDK (seed/backfill/CF) escribe cualquier valor: saltea las reglas", async () => {
      await seedRacha({ rachaSemanas: 3, rachaSemanasUpdatedAt: weeksAgo(1) });
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await assertSucceeds(
          ctx
            .firestore()
            .collection(COL_PROFILES)
            .doc(uid)
            .update({ rachaSemanas: 12 }),
        );
      });
    });
  });
});

// ---------------------------------------------------------------------------
// 9. followersCount / followingCount — CF-write-only (auditoría QA 2026-11-06).
//
// Los mantiene SÓLO `maintainFollowCounters` (Admin SDK) desde #315; el
// cliente no los escribe en ningún camino (`rg followersCount lib/` da sólo
// lectura). Antes el dueño se ponía `{followersCount: 999999}` por REST y su
// perfil público lo mostraba. Re-presentar el valor guardado sigue andando:
// es lo que trae el doc mergeado en cualquier escritura parcial.
// ---------------------------------------------------------------------------
describe("userPublicProfiles rules — contadores de follow (CF-write-only)", () => {
  const uid = "athlete-follow-counters";
  const ref = () => testEnv.authenticatedContext(uid).firestore().collection(COL_PROFILES).doc(uid);

  it.each([
    ["inflar followersCount", { followersCount: 999999 }],
    ["inflar followingCount", { followingCount: 999999 }],
    ["un +1 sin follow detrás", { followersCount: 4 }],
    ["bajarlo a 0", { followersCount: 0 }],
    ["borrarlo", { followersCount: deleteField() }],
  ])("deniega al dueño %s", async (_name, write) => {
    await seed(uid, { userGymId: "gym-a", profile: { followersCount: 3, followingCount: 2 } });
    await assertFails(ref().update(write));
  });

  it("deniega un create que siembra un contador; acepta ausente, null o 0", async () => {
    await seed(uid, { userGymId: "gym-a" });
    await assertFails(setDoc(doc(testEnv.authenticatedContext(uid).firestore(), COL_PROFILES, uid), {
      uid, followersCount: 50,
    }));
    await assertSucceeds(setDoc(doc(testEnv.authenticatedContext(uid).firestore(), COL_PROFILES, uid), {
      uid, followersCount: null, followingCount: 0,
    }));
  });

  it("deja pasar escrituras que no tocan los contadores (los re-presenta el merge)", async () => {
    await seed(uid, { userGymId: "gym-a", profile: { followersCount: 3, followingCount: 2 } });
    await assertSucceeds(ref().set({ workoutsCount: 7, followersCount: 3 }, { merge: true }));
  });

  it("la CF (Admin SDK) los sigue escribiendo", async () => {
    await seed(uid, { userGymId: "gym-a", profile: { followersCount: 3 } });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await assertSucceeds(ctx.firestore().collection(COL_PROFILES).doc(uid).update({ followersCount: 4 }));
    });
  });
});
