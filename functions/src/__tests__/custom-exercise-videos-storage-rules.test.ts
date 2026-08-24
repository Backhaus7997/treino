/**
 * Storage rules tests for the `customExerciseVideos/{userId}/{file=**}` block
 * (#680 Slice E).
 *
 * ⚠️  COBERTURA DELIBERADAMENTE PARCIAL — leer `docs/security.md` §3.3 antes de
 * agregar casos acá. `list` queda SIN test a propósito: hoy
 * `allow read: if request.auth != null` deja que cualquier autenticado enumere
 * tanto `customExerciseVideos/` (devuelve el uid de cada PF que subió videos)
 * como `customExerciseVideos/{uid}/` (devuelve la videoteca entera de ese PF,
 * incluidos los prefijos anidados). Es el leak QA-SEC-008 y sale en su propio
 * PR; testearlo ahora congelaría el status quo (§1.6 regla 1). Cuando cierre,
 * acá van los dos `assertFails` del `listAll`.
 *
 * Lo que sí se pinea acá: escritura owner-only limitada a video, y borrado
 * owner-only. A diferencia de `avatars`, este bloque SÍ declara un
 * `allow delete` propio, así que el borrado funciona y se deniega al ajeno por
 * el motivo correcto (dueño), no por un null deref. Ver §3.2 para el contraste.
 *
 * El bound de 100 MB no se ejercita — mismo criterio que los otros bloques.
 *
 * Correr contra los emuladores (requiere Java 21):
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
import {
  deleteObject,
  getBytes,
  listAll,
  ref,
  uploadString,
} from "firebase/storage";

const PROJECT_ID = "treino-rules-test-custom-exercise-videos";
const RULES_PATH = path.resolve(__dirname, "../../../storage.rules");

const TRAINER = "traineruid";
const OTHER = "otheruid";

const VIDEO_PATH = `customExerciseVideos/${TRAINER}/clip.mp4`;
const NESTED_PATH = `customExerciseVideos/${TRAINER}/2026/deep.mp4`;

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    storage: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: "127.0.0.1",
      port: 9199,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    for (const p of [VIDEO_PATH, NESTED_PATH]) {
      await uploadString(ref(ctx.storage(), p), "seed-bytes", "raw", {
        contentType: "video/mp4",
      });
    }
  });
});

afterEach(async () => {
  await testEnv.clearStorage();
});

function storageAs(uid: string | null) {
  return uid === null
    ? testEnv.unauthenticatedContext().storage()
    : testEnv.authenticatedContext(uid).storage();
}

describe("customExerciseVideos/{userId}/{file=**} — storage rules", () => {
  // --- escritura: owner-only, sólo video -----------------------------------

  it("allows the owner to upload a video under their folder", async () => {
    await assertSucceeds(
      uploadString(
        ref(storageAs(TRAINER), `customExerciseVideos/${TRAINER}/new.mp4`),
        "vid",
        "raw",
        { contentType: "video/mp4" }
      )
    );
  });

  it("allows the owner to upload into a NESTED subfolder", async () => {
    // El wildcard es `{file=**}`: el gate de dueño tiene que seguir valiendo
    // a cualquier profundidad, no sólo en el primer nivel.
    await assertSucceeds(
      uploadString(
        ref(storageAs(TRAINER), `customExerciseVideos/${TRAINER}/a/b/c.mp4`),
        "vid",
        "raw",
        { contentType: "video/mp4" }
      )
    );
  });

  it("DENIES uploading into ANOTHER trainer's folder", async () => {
    await assertFails(
      uploadString(
        ref(storageAs(OTHER), `customExerciseVideos/${TRAINER}/hijack.mp4`),
        "vid",
        "raw",
        { contentType: "video/mp4" }
      )
    );
  });

  it("DENIES uploading into another trainer's NESTED subfolder", async () => {
    await assertFails(
      uploadString(
        ref(storageAs(OTHER), `customExerciseVideos/${TRAINER}/x/hijack.mp4`),
        "vid",
        "raw",
        { contentType: "video/mp4" }
      )
    );
  });

  it("DENIES a non-video contentType even for the owner", async () => {
    await assertFails(
      uploadString(
        ref(storageAs(TRAINER), `customExerciseVideos/${TRAINER}/doc.pdf`),
        "doc",
        "raw",
        { contentType: "application/pdf" }
      )
    );
  });

  it("DENIES an unauthenticated upload", async () => {
    await assertFails(
      uploadString(ref(storageAs(null), VIDEO_PATH), "vid", "raw", {
        contentType: "video/mp4",
      })
    );
  });

  // --- borrado: owner-only, y por el motivo correcto ------------------------

  it("allows the owner to delete their own video", async () => {
    await assertSucceeds(deleteObject(ref(storageAs(TRAINER), VIDEO_PATH)));
  });

  it("DENIES a non-owner delete", async () => {
    await assertFails(deleteObject(ref(storageAs(OTHER), VIDEO_PATH)));
  });

  it("DENIES a non-owner delete in a NESTED subfolder", async () => {
    await assertFails(deleteObject(ref(storageAs(OTHER), NESTED_PATH)));
  });

  // --- lectura: sólo se pinea el piso (anónimo), NO el caso cruzado ---------

  it("DENIES an unauthenticated get", async () => {
    await assertFails(getBytes(ref(storageAs(null), VIDEO_PATH)));
  });

  it("DENIES an unauthenticated list at both levels", async () => {
    // Los casos AUTENTICADOS están abiertos y son QA-SEC-008 — no van acá.
    await assertFails(listAll(ref(storageAs(null), "customExerciseVideos")));
    await assertFails(
      listAll(ref(storageAs(null), `customExerciseVideos/${TRAINER}`))
    );
  });
});
