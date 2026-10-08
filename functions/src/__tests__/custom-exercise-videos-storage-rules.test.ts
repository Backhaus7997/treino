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
  uploadBytes,
  uploadString,
} from "firebase/storage";
import { doc, setDoc } from "firebase/firestore";

/**
 * ⚠️ El projectId NO puede ser uno arbitrario desde que el `write` de este
 * bloque hace `firestore.get()`. `firebase.json` tiene
 * `emulators.singleProjectMode: true`, que pinea las llamadas cross-service de
 * las reglas de Storage al proyecto POR DEFECTO del emulador sin importar qué
 * projectId pida este proceso. Con un id propio, el doc de usuario se siembra
 * bajo MI proyecto y la regla lo busca bajo el default: el `get` devuelve null,
 * el alumno enforced cae en la rama fail-open y los tests del TOPE FREE dan
 * verde sin que el tope exista.
 *
 * Es el mismo pisón que ya documentan `session-feedback-storage-rules.test.ts`
 * y `scripts/rules_test/chat-media-storage.test.js` — los otros dos bloques de
 * Storage que hacen firestore.get(). Se lee de `GCLOUD_PROJECT`, que
 * `emulators:exec` exporta con el proyecto ya resuelto.
 *
 * Este archivo tenía un id propio ("treino-rules-test-custom-exercise-videos")
 * mientras el bloque era puro Storage, que era correcto entonces.
 */
const PROJECT_ID = process.env.GCLOUD_PROJECT ?? "treino-dev";
const RULES_PATH = path.resolve(__dirname, "../../../storage.rules");
const FIRESTORE_RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const TRAINER = "traineruid";
const OTHER = "otheruid";
const ATHLETE = "athleteuid";

const MB = 1024 * 1024;

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
    // El `write` de este bloque hace firestore.get() sobre `users/{uid}` para
    // resolver el tier y leer el contador denormalizado, así que la suite
    // necesita el emulador de Firestore además del de Storage.
    firestore: {
      rules: fs.readFileSync(FIRESTORE_RULES_PATH, "utf8"),
      host: "127.0.0.1",
      port: 8080,
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
  await testEnv.clearFirestore();
});

/**
 * Siembra `users/{uid}` con las reglas apagadas.
 *
 * `athletePaywallEnforced` y `customExerciseVideoUsage` son los dos campos
 * CF-write-only que la regla de Storage lee. Sembrarlos con las reglas
 * ENCENDIDAS es imposible a propósito: `firestore.rules` los pinea justamente
 * para que el alumno no se auto-exima.
 */
async function seedUser(
  uid: string,
  data: Record<string, unknown>
): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users", uid), { uid, ...data });
  });
}

/** Sube `bytes` bytes de video a `path` como `uid`. */
function uploadVideoOf(uid: string, path: string, bytes: number) {
  return uploadBytes(ref(storageAs(uid), path), new Uint8Array(bytes), {
    contentType: "video/mp4",
  });
}

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

  // --- tope de costo: tamaño por archivo y cantidad, por tier --------------
  //
  // El bloque tenía cap de TAMAÑO (100 MB) y ninguno de CANTIDAD, y el paywall
  // del alumno no lo tocaba. Lo que se pinea acá es el corte por tier: el
  // alumno enforced entra en 25 MB × 3 videos; el PF y el alumno que paga
  // conservan el techo estructural de 100 MB × 50.
  //
  // El bound estructural de 100 MB sigue SIN ejercitarse, igual que antes:
  // subir 101 MB al emulador cuesta más de lo que prueba. El de 25 MB sí se
  // ejercita porque es la rama NUEVA — si no, el corte por tier se shipearía
  // sin un solo test encima, que es exactamente lo que este archivo evita.

  it("permite 10 MB a un alumno con el paywall aplicado", async () => {
    await seedUser(ATHLETE, { role: "athlete", athletePaywallEnforced: true });
    await assertSucceeds(
      uploadVideoOf(ATHLETE, `customExerciseVideos/${ATHLETE}/ok.mp4`, 10 * MB)
    );
  });

  it("DENIEGA 26 MB a un alumno con el paywall aplicado", async () => {
    await seedUser(ATHLETE, { role: "athlete", athletePaywallEnforced: true });
    await assertFails(
      uploadVideoOf(ATHLETE, `customExerciseVideos/${ATHLETE}/big.mp4`, 26 * MB)
    );
  });

  it("permite 26 MB a un PF — el tope free NO le aplica", async () => {
    // El caso que rompería la videoteca de TODOS los PF si el gate se colgara
    // de `athleteEntitlementProvider` en vez de `athletePaywallEnforced`: ese
    // provider no mira `role` y devuelve `free` para un PF.
    // `resolveAthletePaywallEnforced` sí lo mira y corta en
    // `if (userData?.role !== "athlete") return false`.
    await seedUser(TRAINER, { role: "trainer", athletePaywallEnforced: false });
    await assertSucceeds(
      uploadVideoOf(TRAINER, `customExerciseVideos/${TRAINER}/big.mp4`, 26 * MB)
    );
  });

  it("permite el video 3 a un alumno con 2 ya subidos", async () => {
    // Frontera inferior del tope de cantidad: con `count` en 2 todavía entra.
    await seedUser(ATHLETE, {
      role: "athlete",
      athletePaywallEnforced: true,
      customExerciseVideoUsage: { count: 2, bytes: 2 * MB },
    });
    await assertSucceeds(
      uploadVideoOf(ATHLETE, `customExerciseVideos/${ATHLETE}/c.mp4`, 1024)
    );
  });

  it("DENIEGA el video 4 a un alumno con 3 ya subidos", async () => {
    // El agujero original: el tamaño estaba acotado, la CANTIDAD no. Un
    // archivo de 1 KB da rojo acá, así que lo que deniega es el contador y no
    // el tamaño — si fuera al revés este test pasaría por el motivo equivocado.
    await seedUser(ATHLETE, {
      role: "athlete",
      athletePaywallEnforced: true,
      customExerciseVideoUsage: { count: 3, bytes: 3 * MB },
    });
    await assertFails(
      uploadVideoOf(ATHLETE, `customExerciseVideos/${ATHLETE}/d.mp4`, 1024)
    );
  });

  it("permite el video 4 a un PF — el tope free de cantidad NO le aplica", async () => {
    await seedUser(TRAINER, {
      role: "trainer",
      athletePaywallEnforced: false,
      customExerciseVideoUsage: { count: 3, bytes: 3 * MB },
    });
    await assertSucceeds(
      uploadVideoOf(TRAINER, `customExerciseVideos/${TRAINER}/d.mp4`, 1024)
    );
  });

  it("DENIEGA la subida 51 hasta a un PF — techo estructural", async () => {
    // No es paywall: es el techo del producto, y aplica pague o no. Sin él una
    // cuenta `trainer` tiene subida ilimitada de 100 MB.
    await seedUser(TRAINER, {
      role: "trainer",
      athletePaywallEnforced: false,
      customExerciseVideoUsage: { count: 50, bytes: 50 * MB },
    });
    await assertFails(
      uploadVideoOf(TRAINER, `customExerciseVideos/${TRAINER}/x.mp4`, 1024)
    );
  });

  it("permite subir a un usuario SIN doc de perfil — fail open", async () => {
    // `firestore.get()` devuelve null y hay escrituras legítimas de usuarios
    // sin doc todavía. Mismo default seguro que `paywallEnforcedFor` en
    // `firestore.rules`: sin doc ⇒ no enforced. El techo estructural sigue.
    await assertSucceeds(
      uploadVideoOf(OTHER, `customExerciseVideos/${OTHER}/nodoc.mp4`, 10 * MB)
    );
  });
});
