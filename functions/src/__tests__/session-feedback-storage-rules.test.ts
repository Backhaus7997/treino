/**
 * Storage rules tests para `sessionFeedback/{userId}/{sessionId}/{fileName}`
 * (#628) — la foto opcional que acompaña un comentario o una molestia que el
 * alumno reporta durante la sesión.
 *
 * POR QUÉ ESTE BLOQUE NO SE PARECE A postPhotos
 * Los cinco bloques que ya existían dan `get` a cualquier autenticado. Acá no
 * se puede: la foto es "dónde me duele", dato de salud. El `get` se gatea con
 * el MISMO grant de dos partes que gobierna la sesión en firestore.rules,
 * usando la llamada cross-service `firestore.get()` que ya prueba `chatMedia`.
 *
 * Y `list` va cerrado incondicionalmente, como en postPhotos/chatMedia y NO
 * como en avatars/customExerciseVideos — los dos leaks confirmados
 * (QA-SEC-007 / QA-SEC-008, docs/security.md §3.6). Acá enumerar el prefijo
 * `sessionFeedback/{uid}/` publicaría EN QUÉ SESIONES un alumno reportó dolor
 * sin bajar un solo byte: el nombre del prefijo ya es el dato sensible.
 *
 * LO QUE ESTE ARCHIVO **NO** PRUEBA, y hay que leerlo antes de confiar en el
 * verde: que la foto esté protegida. No lo está por estas reglas. La URL de
 * `getDownloadURL()` lleva `?alt=media&token=`, es una credencial al portador
 * y NO evalúa storage.rules (docs/security.md §3.1, medido: HTTP 200 sin
 * ningún header de auth). El gate real es el documento de Firestore donde vive
 * esa URL — `users/{uid}/sessions/{sid}/exerciseFeedback/{id}` — y lo cubre
 * `exercise-feedback-rules.test.ts`. Este bloque es defensa en profundidad
 * para el único camino que sí pasa por las reglas: resolver el objeto por
 * `ref()`.
 *
 * El bound de 15 MB NO se ejercita: empujar ese cuerpo por el emulador en cada
 * corrida es lastre de CI puro, y es el mismo idiom `request.resource.size`
 * que ya corre en los otros cinco bloques (mismo criterio que
 * post-photos-storage-rules.test.ts).
 *
 * Run against the emulators (Java 21 required):
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
import { doc, setDoc, deleteDoc } from "firebase/firestore";

/**
 * ⚠️ El projectId NO puede ser uno arbitrario acá, y esto costó una vuelta:
 * `firebase.json` tiene `emulators.singleProjectMode: true`, que pinea las
 * llamadas cross-service `firestore.get()` de las reglas de Storage al
 * proyecto POR DEFECTO del emulador, sin importar qué projectId pida este
 * proceso. Con un id propio, el grant se siembra bajo MI proyecto y la regla
 * lo busca bajo el default: el `get` del PF se cae con un error de evaluación
 * y el test miente diciendo "el gate funciona".
 *
 * Es el mismo pisón que ya documenta `scripts/rules_test/chat-media-storage.test.js`
 * (líneas 22-30) — el otro bloque de Storage que hace firestore.get().
 *
 * El default NO es el mismo en los dos caminos que corren esta suite:
 *   - local, `npm run test:rules:emulator` → `--project treino-rules-test`
 *   - CI, job *Functions Test*             → sin `--project`, o sea `.firebaserc` = `treino-dev`
 * así que se lee de `GCLOUD_PROJECT`, que `emulators:exec` exporta con el
 * proyecto ya resuelto. Si algún día se resolviera mal, el efecto es un ROJO
 * ruidoso en "permite al PF nombrado en el grant bajarla", no un verde falso.
 */
const PROJECT_ID = process.env.GCLOUD_PROJECT ?? "treino-dev";
const STORAGE_RULES_PATH = path.resolve(__dirname, "../../../storage.rules");
const FIRESTORE_RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const ATHLETE = "athlete-sfb";
const TRAINER = "trainer-sfb";
const OTHER = "other-sfb";

const SESSION_ID = "session-sfb-1";
const PHOTO_PATH = `sessionFeedback/${ATHLETE}/${SESSION_ID}/f1.jpg`;

/** Todo objeto que esta suite puede llegar a dejar en el bucket. */
const SEEDED_OBJECTS = [
  PHOTO_PATH,
  `sessionFeedback/${ATHLETE}/${SESSION_ID}/f2.jpg`,
  `sessionFeedback/${ATHLETE}/${SESSION_ID}/f3.mp4`,
  `sessionFeedback/${ATHLETE}/${SESSION_ID}/pf.jpg`,
  `sessionFeedback/${ATHLETE}/${SESSION_ID}/hijack.jpg`,
  `sessionFeedback/${ATHLETE}/${SESSION_ID}/anon.jpg`,
];

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    storage: {
      rules: fs.readFileSync(STORAGE_RULES_PATH, "utf8"),
      host: "127.0.0.1",
      port: 9199,
    },
    // El `get` de este bloque hace firestore.get() sobre session_shares, así
    // que la suite necesita el emulador de Firestore además del de Storage.
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
  // Semilla de la foto con las reglas apagadas, para tener blanco de lectura.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await uploadString(ref(ctx.storage(), PHOTO_PATH), "seed-bytes", "raw", {
      contentType: "image/jpeg",
    });
  });
});

afterEach(async () => {
  // Limpieza QUIRÚRGICA, no `clearStorage()` + `clearFirestore()`. Como el
  // projectId es el default del emulador (ver arriba), esta suite comparte
  // namespace con TODAS las demás de functions/. Un clear global acá le
  // borraría los datos a cualquier otra suite que corriera en paralelo —
  // hoy CI usa `--runInBand` y no pasaría, pero eso es una propiedad del
  // comando, no de este archivo, y `npm test` a secas SÍ paraleliza.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const bucket = ctx.storage();
    for (const p of SEEDED_OBJECTS) {
      await deleteObject(ref(bucket, p)).catch(() => undefined);
    }
    await deleteDoc(doc(ctx.firestore(), "session_shares", ATHLETE)).catch(
      () => undefined,
    );
  });
});

function storageAs(uid: string | null) {
  return uid === null
    ? testEnv.unauthenticatedContext().storage()
    : testEnv.authenticatedContext(uid).storage();
}

/** Otorga `session_shares/{ATHLETE}` saltando las reglas de Firestore. */
async function seedGrant(trainerId: string): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "session_shares", ATHLETE), {
      trainerId,
      updatedAt: new Date(),
    });
  });
}

async function revokeGrant(): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await deleteDoc(doc(ctx.firestore(), "session_shares", ATHLETE));
  });
}

describe("sessionFeedback — write", () => {
  it("permite al dueño subir una imagen bajo su carpeta", async () => {
    await assertSucceeds(
      uploadString(
        ref(storageAs(ATHLETE), `sessionFeedback/${ATHLETE}/${SESSION_ID}/f2.jpg`),
        "img",
        "raw",
        { contentType: "image/jpeg" },
      ),
    );
  });

  it("DENIEGA subir en la carpeta de OTRO usuario", async () => {
    await assertFails(
      uploadString(
        ref(storageAs(OTHER), `sessionFeedback/${ATHLETE}/${SESSION_ID}/hijack.jpg`),
        "img",
        "raw",
        { contentType: "image/jpeg" },
      ),
    );
  });

  it("DENIEGA que el PF con grant escriba — el canal es one-way", async () => {
    // El grant abre la LECTURA. Que el PF pueda plantar una foto en la sesión
    // del alumno sería otra cosa completamente distinta.
    await seedGrant(TRAINER);
    await assertFails(
      uploadString(
        ref(storageAs(TRAINER), `sessionFeedback/${ATHLETE}/${SESSION_ID}/pf.jpg`),
        "img",
        "raw",
        { contentType: "image/jpeg" },
      ),
    );
  });

  it("DENIEGA un contentType que no sea imagen, aun para el dueño", async () => {
    await assertFails(
      uploadString(
        ref(storageAs(ATHLETE), `sessionFeedback/${ATHLETE}/${SESSION_ID}/f3.mp4`),
        "vid",
        "raw",
        { contentType: "video/mp4" },
      ),
    );
  });

  it("DENIEGA la subida anónima", async () => {
    await assertFails(
      uploadString(
        ref(storageAs(null), `sessionFeedback/${ATHLETE}/${SESSION_ID}/anon.jpg`),
        "img",
        "raw",
        { contentType: "image/jpeg" },
      ),
    );
  });
});

describe("sessionFeedback — get, gateado por session_shares", () => {
  it("permite al dueño bajar su foto SIN que exista el grant", async () => {
    // El dueño va primero en el `||`: su lectura no depende del documento que
    // mantiene la CF de entitlements. Si este caso cae, el `||` está al revés.
    await assertSucceeds(getBytes(ref(storageAs(ATHLETE), PHOTO_PATH)));
  });

  it("permite al PF nombrado en el grant bajarla", async () => {
    await seedGrant(TRAINER);
    await assertSucceeds(getBytes(ref(storageAs(TRAINER), PHOTO_PATH)));
  });

  it("DENIEGA a un autenticado cualquiera — NO es `request.auth != null`", async () => {
    // Este es EL caso del bloque. Los otros cinco paths de storage.rules
    // dejan pasar acá; este no puede, porque la foto es dato de salud.
    await seedGrant(TRAINER);
    await assertFails(getBytes(ref(storageAs(OTHER), PHOTO_PATH)));
  });

  it("DENIEGA a un PF distinto del que nombra el grant", async () => {
    await seedGrant(TRAINER);
    await assertFails(getBytes(ref(storageAs(OTHER), PHOTO_PATH)));
  });

  it("DENIEGA a cualquier PF cuando NO hay documento de grant", async () => {
    // firestore.exists() primero: sin doc, la regla deniega en vez de romper.
    await assertFails(getBytes(ref(storageAs(TRAINER), PHOTO_PATH)));
  });

  it("DENIEGA al PF de nuevo en cuanto el alumno revoca el grant", async () => {
    await seedGrant(TRAINER);
    await assertSucceeds(getBytes(ref(storageAs(TRAINER), PHOTO_PATH)));

    await revokeGrant();

    await assertFails(getBytes(ref(storageAs(TRAINER), PHOTO_PATH)));
  });

  it("DENIEGA el get anónimo", async () => {
    await assertFails(getBytes(ref(storageAs(null), PHOTO_PATH)));
  });
});

describe("sessionFeedback — list cerrado en los tres niveles", () => {
  it("DENIEGA listar la carpeta de la sesión, incluso al dueño y al PF", async () => {
    await seedGrant(TRAINER);
    const folder = `sessionFeedback/${ATHLETE}/${SESSION_ID}`;
    await assertFails(listAll(ref(storageAs(ATHLETE), folder)));
    await assertFails(listAll(ref(storageAs(TRAINER), folder)));
    await assertFails(listAll(ref(storageAs(OTHER), folder)));
  });

  it("DENIEGA listar la carpeta del alumno — en qué sesiones reportó dolor", async () => {
    await seedGrant(TRAINER);
    const folder = `sessionFeedback/${ATHLETE}`;
    await assertFails(listAll(ref(storageAs(ATHLETE), folder)));
    await assertFails(listAll(ref(storageAs(TRAINER), folder)));
    await assertFails(listAll(ref(storageAs(OTHER), folder)));
  });

  it("DENIEGA listar la raíz sessionFeedback/ — sin padrón de uids", async () => {
    // La raíz no la cubre `allow list: if false` (ese match pide tres
    // segmentos) sino el catch-all `{allPaths=**}`. Sin este caso, un
    // `match /sessionFeedback/{p=**}` agregado sin cuidado abriría la
    // enumeración de qué alumnos reportaron molestias y ningún test se
    // pondría rojo. Mismo razonamiento que en post-photos §3.4.
    await assertFails(listAll(ref(storageAs(ATHLETE), "sessionFeedback")));
    await assertFails(listAll(ref(storageAs(OTHER), "sessionFeedback")));
  });
});

describe("sessionFeedback — delete", () => {
  it("permite al dueño borrar su foto", async () => {
    // §3.8 regla 3: el bloque usa `request.resource.<algo>` en el write, así
    // que necesita su `allow delete` PROPIO o el borrado falla en silencio —
    // la lección de QA-SEC-009 en avatars.
    await assertSucceeds(deleteObject(ref(storageAs(ATHLETE), PHOTO_PATH)));
  });

  it("DENIEGA que el PF con grant borre el reporte", async () => {
    await seedGrant(TRAINER);
    await assertFails(deleteObject(ref(storageAs(TRAINER), PHOTO_PATH)));
  });

  it("DENIEGA el borrado de un tercero y el anónimo", async () => {
    await assertFails(deleteObject(ref(storageAs(OTHER), PHOTO_PATH)));
    await assertFails(deleteObject(ref(storageAs(null), PHOTO_PATH)));
  });
});
