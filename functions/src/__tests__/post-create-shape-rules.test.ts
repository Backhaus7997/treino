/**
 * Shape-hardening tests for `posts/{postId}` create/update rules
 * (share-composer PR1).
 *
 * Before this change, posts had the laxest write rules in the file: create
 * only checked `authorUid == auth.uid` — no key allowlist, no bounds. Any
 * authenticated user could write arbitrary keys and megabyte-sized strings
 * into their own posts. The rule now enforces:
 *   - keys().hasOnly(the 10 legacy fields + photoUrl + workoutSnapshot)
 *   - text is string && size <= 1120 — anti-abuse cap, NOT a mirror of the
 *     280-character client cap: rules size() counts encoding units, so a
 *     280 bound would deny legit max-length text with tildes/emoji
 *   - privacy in ['friends','gym','public']
 *   - photoUrl optional, <= 600 chars (optStrMaxLen — present-with-null is
 *     the normal json_serializable wire shape and must pass)
 *   - workoutSnapshot optional; when present: map with `exercises` list of
 *     <= 30 entries (mirror of kMaxSnapshotExercises). The nested set shape
 *     is deliberately NOT validated — the 1 MiB doc limit is the backstop.
 *
 * BIDIRECTIONAL retro-compat during the rules-deploy window is pinned here:
 * a legacy-shaped post (10 fields, no photoUrl/workoutSnapshot) must pass the
 * NEW rules — and the new client omits nothing the old rules reject, since
 * the old create rule only checked authorUid.
 *
 * Run against the Firestore emulator (Java 21 required):
 *   npm --prefix functions run test:rules:emulator
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

// Distinct projectId so this suite runs in its own emulator namespace and its
// clearFirestore() never wipes another parallel rules suite's seed data.
const PROJECT_ID = "treino-rules-test-post-shape";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const AUTHOR = "author-uid";
const OTHER = "other-uid";

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
 * Full new-client wire shape: post.toJson() emits EVERY key, optional ones
 * as explicit null (no includeIfNull:false on these models).
 */
function validPost(overrides: Record<string, unknown> = {}) {
  return {
    id: "p1",
    authorUid: AUTHOR,
    authorDisplayName: "Ana",
    authorAvatarUrl: null,
    authorGymId: null,
    text: "¡Terminé mi entreno! 💪",
    routineTag: { routineId: "r1", routineName: "Push" },
    privacy: "friends",
    createdAt: new Date(),
    workoutStats: { volumeKg: 1200, durationMin: 45, exerciseCount: 5 },
    photoUrl: null,
    workoutSnapshot: null,
    ...overrides,
  };
}

/** A snapshot with [count] exercises in the embedded wire shape. */
function snapshotWith(count: number) {
  return {
    exercises: Array.from({ length: count }, (_, i) => ({
      exerciseName: `Ejercicio ${i}`,
      sets: [
        {
          id: `s${i}`,
          exerciseId: `e${i}`,
          exerciseName: `Ejercicio ${i}`,
          setNumber: 1,
          reps: 10,
          weightKg: 50,
          rpe: null,
          completedAt: new Date(),
        },
      ],
    })),
    setsByAxis: { chest: count },
    volumeKgByAxis: { chest: 500.0 },
    truncated: false,
  };
}

function createPost(uid: string, data: Record<string, unknown>) {
  return testEnv
    .authenticatedContext(uid)
    .firestore()
    .collection("posts")
    .doc("p1")
    .set(data);
}

describe("posts/{postId} create — shape hardening", () => {
  it("allows a full new-client post (photoUrl + workoutSnapshot present-null)", async () => {
    await assertSucceeds(createPost(AUTHOR, validPost()));
  });

  it("allows a legacy-shaped post (10 fields, sin photoUrl/workoutSnapshot) — retro-compat", async () => {
    const legacy = validPost();
    delete (legacy as Record<string, unknown>).photoUrl;
    delete (legacy as Record<string, unknown>).workoutSnapshot;
    await assertSucceeds(createPost(AUTHOR, legacy));
  });

  it("allows a post with a real photoUrl and a real snapshot", async () => {
    await assertSucceeds(
      createPost(
        AUTHOR,
        validPost({
          photoUrl:
            "https://firebasestorage.googleapis.com/v0/b/x/o/postPhotos%2Fu%2Fp1.jpg?alt=media&token=t",
          workoutSnapshot: snapshotWith(3),
        })
      )
    );
  });

  it("DENIES a non-owner create (SCENARIO-130 regression)", async () => {
    await assertFails(createPost(OTHER, validPost()));
  });

  it("DENIES an extra key outside the allowlist", async () => {
    await assertFails(createPost(AUTHOR, validPost({ hacked: true })));
  });

  it("DENIES text over the 1120 anti-abuse bound", async () => {
    await assertFails(
      createPost(AUTHOR, validPost({ text: "x".repeat(1121) }))
    );
  });

  it("allows text of exactly 1120", async () => {
    await assertSucceeds(
      createPost(AUTHOR, validPost({ text: "x".repeat(1120) }))
    );
  });

  it("allows an emoji-heavy 280-emoji text (the reason the bound is NOT 280)", async () => {
    // 280 graphemes of U+1F4AA measure 1120 via rules size() (it counts
    // encoding units, NOT user-visible characters — probed against the
    // emulator when this suite was written: a 280 bound denied this text).
    // The client caps at 280 CHARACTERS (kMaxPostChars); rules cap at
    // 280 × 4 = 1120 so max-length text with tildes/CJK/emoji still passes.
    await assertSucceeds(
      createPost(AUTHOR, validPost({ text: "💪".repeat(280) }))
    );
  });

  it("allows max-length accented Spanish text (2-byte chars)", async () => {
    await assertSucceeds(
      createPost(AUTHOR, validPost({ text: "á".repeat(280) }))
    );
  });

  it("DENIES a non-string text", async () => {
    await assertFails(createPost(AUTHOR, validPost({ text: 123 })));
  });

  it("DENIES garbage privacy", async () => {
    await assertFails(createPost(AUTHOR, validPost({ privacy: "everyone" })));
  });

  it("DENIES photoUrl over 600 chars", async () => {
    await assertFails(
      createPost(AUTHOR, validPost({ photoUrl: `https://x/${"a".repeat(600)}` }))
    );
  });

  it("DENIES a non-map workoutSnapshot", async () => {
    await assertFails(
      createPost(AUTHOR, validPost({ workoutSnapshot: "not-a-map" }))
    );
  });

  it("DENIES an empty-map workoutSnapshot (sin exercises list)", async () => {
    await assertFails(createPost(AUTHOR, validPost({ workoutSnapshot: {} })));
  });

  it("DENIES workoutSnapshot.exercises that is not a list", async () => {
    await assertFails(
      createPost(
        AUTHOR,
        validPost({ workoutSnapshot: { exercises: "nope" } })
      )
    );
  });

  it("DENIES a snapshot with more than 30 exercises", async () => {
    await assertFails(
      createPost(AUTHOR, validPost({ workoutSnapshot: snapshotWith(31) }))
    );
  });

  it("allows a snapshot with exactly 30 exercises", async () => {
    await assertSucceeds(
      createPost(AUTHOR, validPost({ workoutSnapshot: snapshotWith(30) }))
    );
  });
});

describe("posts/{postId} update — same shape bounds as create", () => {
  beforeEach(async () => {
    // Seed a legacy-shaped post owned by AUTHOR (rules disabled).
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("posts").doc("p1").set({
        authorUid: AUTHOR,
        privacy: "friends",
        text: "original",
      });
    });
  });

  function updatePost(uid: string, data: Record<string, unknown>) {
    return testEnv
      .authenticatedContext(uid)
      .firestore()
      .collection("posts")
      .doc("p1")
      .update(data);
  }

  it("allows the author's normal edit (text/privacy/routineTag)", async () => {
    await assertSucceeds(
      updatePost(AUTHOR, {
        text: "editado",
        privacy: "public",
        routineTag: null,
      })
    );
  });

  it("DENIES a non-author update", async () => {
    await assertFails(updatePost(OTHER, { text: "hijacked" }));
  });

  it("DENIES an update that inflates text over the 1120 bound", async () => {
    await assertFails(updatePost(AUTHOR, { text: "x".repeat(1121) }));
  });

  it("DENIES an update that smuggles a new key", async () => {
    await assertFails(updatePost(AUTHOR, { text: "ok", hacked: true }));
  });

  it("DENIES an update to garbage privacy", async () => {
    await assertFails(updatePost(AUTHOR, { privacy: "everyone" }));
  });

  it("DENIES an update that swells the snapshot over 30 exercises", async () => {
    await assertFails(
      updatePost(AUTHOR, { workoutSnapshot: snapshotWith(31) })
    );
  });

  // Immutable-field pins: without them, the post's own author could REASSIGN
  // authorUid and plant a fake post attributed to someone else (visible in the
  // victim's friends' feeds), or inject into another gym via authorGymId.
  it("DENIES the author reassigning authorUid (identity spoofing)", async () => {
    await assertFails(
      updatePost(AUTHOR, { authorUid: OTHER, text: "contenido falso" })
    );
  });

  it("DENIES the author reassigning authorGymId (cross-gym injection)", async () => {
    await assertFails(updatePost(AUTHOR, { authorGymId: "gym-ajeno" }));
  });

  it("DENIES rewriting authorDisplayName on edit", async () => {
    await assertFails(updatePost(AUTHOR, { authorDisplayName: "Impostor" }));
  });

  it("DENIES rewriting createdAt on edit", async () => {
    await assertFails(updatePost(AUTHOR, { createdAt: new Date() }));
  });
});
