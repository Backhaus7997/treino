/**
 * Storage rules tests for the `customExerciseVideos/{userId}/{file=**}` block
 * (#680 Slice E; `list` cerrado por QA-SEC-008 / #763).
 *
 * ⚠️  COBERTURA DELIBERADAMENTE PARCIAL — leer `docs/security.md` §3.3 antes de
 * agregar casos acá.
 *
 * `list` está cerrado incondicionalmente y se pinea en los dos niveles: la
 * raíz `customExerciseVideos/` (que devolvía el uid de cada PF con videos) y
 * la carpeta `customExerciseVideos/{uid}/` (que devolvía la videoteca entera,
 * recursivamente). Los dos casos van también para el DUEÑO: la regla es
 * `if false`, no owner-only, y si alguien la aflojara a `request.auth.uid ==
 * userId` el caso ajeno seguiría rojo y nadie se enteraría.
 *
 * `get` amplio queda SIN pinear a propósito: es un permiso deliberado (§3.3),
 * pero un `assertSucceeds` ahí congelaría el status quo — si mañana se decide
 * apretarlo a owner-only, el test tendría que borrarse en vez de guiar. Sí se
 * pinea el piso anónimo.
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

  // --- get: sólo se pinea el piso (anónimo), NO el caso cruzado ------------

  it("DENIES an unauthenticated get", async () => {
    await assertFails(getBytes(ref(storageAs(null), VIDEO_PATH)));
  });

  // --- list: cerrado incondicionalmente (QA-SEC-008) ------------------------

  it("DENIES listing a trainer's video folder — even the owner's own", async () => {
    // Este era el leak caro: `allow read` cubría `list`, y con `{file=**}` la
    // enumeración era recursiva, así que un atleta con cuenta gratis se
    // llevaba la videoteca completa de cualquier PF. Ver `docs/security.md`
    // §3.3. La regla es `if false`, no owner-only: por eso el dueño también
    // tiene que dar rojo.
    await assertFails(
      listAll(ref(storageAs(OTHER), `customExerciseVideos/${TRAINER}`))
    );
    await assertFails(
      listAll(ref(storageAs(TRAINER), `customExerciseVideos/${TRAINER}`))
    );
  });

  it("DENIES listing the customExerciseVideos/ root — no uid enumeration", async () => {
    // La raíz devolvía `prefixes=[customExerciseVideos/{uid}]`: un directorio
    // de qué PFs tienen contenido propio, que no existe en ninguna otra parte
    // del producto. A diferencia de `postPhotos/` (donde la raíz la cierra el
    // catch-all porque ese match pide dos segmentos), acá el `{file=**}` la
    // hace caer dentro de ESTE bloque — por eso la cierra el `allow list`.
    await assertFails(listAll(ref(storageAs(OTHER), "customExerciseVideos")));
    await assertFails(listAll(ref(storageAs(TRAINER), "customExerciseVideos")));
  });

  it("DENIES an unauthenticated list at both levels", async () => {
    await assertFails(listAll(ref(storageAs(null), "customExerciseVideos")));
    await assertFails(
      listAll(ref(storageAs(null), `customExerciseVideos/${TRAINER}`))
    );
  });
});
