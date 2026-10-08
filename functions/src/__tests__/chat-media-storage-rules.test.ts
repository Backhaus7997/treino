/**
 * Storage rules tests del TOPE DE COSTO de `chatMedia/{chatId}/{userId}/{file=**}`
 * (#chat-media-quota).
 *
 * Este archivo cubre el `write`: caps por archivo, tier, y el tope de BYTES
 * TOTALES. El gate de MEMBRESÍA del `get`/`list` —que es otra cosa y es
 * anterior— lo cubre `scripts/rules_test/chat-media-storage.test.js`, y no se
 * duplica acá.
 *
 * ⚠️ EL PROJECT ID NO PUEDE SER UNO ARBITRARIO. `firebase.json` tiene
 * `emulators.singleProjectMode: true`, que pinea las llamadas cross-service
 * `firestore.get()` de las reglas de Storage al proyecto POR DEFECTO del
 * emulador, sin importar qué projectId pida este proceso. Con un id propio, el
 * doc de `users` se siembra bajo MI proyecto y la regla lo busca bajo el
 * default: la lectura devuelve null, el fail-open deja pasar TODO, y la suite
 * da verde falso sobre un tope que no corrió. Mismo encabezado que
 * `session-feedback-storage-rules.test.ts` y
 * `custom-exercise-videos-storage-rules.test.ts`.
 *
 * Correr contra los emuladores (Java 21):
 *   firebase emulators:exec --only firestore,auth,storage \
 *     --project treino-rules-test \
 *     "npm --prefix functions test -- --runInBand chat-media-storage-rules"
 *
 * `--runInBand` NO es opcional: dos workers compartiendo el mismo emulador se
 * pisan el estado entre `clearStorage()` y `clearFirestore()`.
 */

import * as fs from "fs";
import * as path from "path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { deleteObject, ref, uploadBytes } from "firebase/storage";
import { doc, setDoc } from "firebase/firestore";

const PROJECT_ID = process.env.GCLOUD_PROJECT ?? "treino-dev";
const RULES_PATH = path.resolve(__dirname, "../../../storage.rules");
const FIRESTORE_RULES_PATH = path.resolve(
  __dirname,
  "../../../firestore.rules",
);

const ATHLETE = "athleteuid";
const TRAINER = "traineruid";
const OTHER = "otheruid";
// `ChatRepository.chatIdFor` = sorted([a, b]).join('_').
const CHAT_ID = `${ATHLETE}_${TRAINER}`;

const MB = 1024 * 1024;
const GB = 1024 * MB;

const FREE_TOTAL = 250 * MB;
const MAX_TOTAL = 5 * GB;

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

afterEach(async () => {
  await testEnv.clearStorage();
  await testEnv.clearFirestore();
});

/**
 * Siembra `users/{uid}` con las reglas APAGADAS.
 *
 * `athletePaywallEnforced` y `chatMediaUsage` son los dos campos CF-write-only
 * que la regla de Storage lee. Sembrarlos con las reglas encendidas es
 * imposible a propósito: `firestore.rules` los pinea justamente para que el
 * alumno no se auto-exima.
 */
async function seedUser(
  uid: string,
  data: Record<string, unknown>,
): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users", uid), { uid, ...data });
  });
}

function storageAs(uid: string) {
  return testEnv.authenticatedContext(uid).storage();
}

/** Sube `bytes` bytes con `contentType` a `path`, como `uid`. */
function upload(
  uid: string,
  objectPath: string,
  bytes: number,
  contentType: string,
) {
  return uploadBytes(
    ref(storageAs(uid), objectPath),
    new Uint8Array(bytes),
    { contentType },
  );
}

const imageOf = (uid: string, name: string, bytes: number) =>
  upload(uid, `chatMedia/${CHAT_ID}/${uid}/${name}`, bytes, "image/jpeg");

const videoOf = (uid: string, name: string, bytes: number) =>
  upload(uid, `chatMedia/${CHAT_ID}/${uid}/${name}`, bytes, "video/mp4");

describe("chatMedia — el gate de dueño y de contentType sigue en pie", () => {
  it("deja al dueño subir una foto en su carpeta", async () => {
    await assertSucceeds(imageOf(ATHLETE, "ok.jpg", 1024));
  });

  it("deja al dueño subir a una subcarpeta ANIDADA — el match es {file=**}", async () => {
    await assertSucceeds(
      upload(
        ATHLETE,
        `chatMedia/${CHAT_ID}/${ATHLETE}/2026/09/ok.jpg`,
        1024,
        "image/jpeg",
      ),
    );
  });

  it("DENIEGA subir a la carpeta de OTRO usuario del mismo chat", async () => {
    await assertFails(
      upload(
        OTHER,
        `chatMedia/${CHAT_ID}/${ATHLETE}/hijack.jpg`,
        1024,
        "image/jpeg",
      ),
    );
  });

  it("DENIEGA un contentType que no es imagen ni video", async () => {
    await assertFails(
      upload(
        ATHLETE,
        `chatMedia/${CHAT_ID}/${ATHLETE}/plan.pdf`,
        1024,
        "application/pdf",
      ),
    );
  });

  it("deja al dueño BORRAR — el bloque tiene su `allow delete` propio", async () => {
    // `docs/security.md` §3.8 regla 3: en un delete `request.resource` es null,
    // así que un bloque que lo dereferencia necesita su propia regla o el
    // borrado se deniega hasta para el dueño. `chatMediaWriteAllowed()` lee
    // `request.resource.size`, o sea que este test es el que avisa si alguien
    // mueve ese chequeo al `delete`.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(
        ref(ctx.storage(), `chatMedia/${CHAT_ID}/${ATHLETE}/borrable.jpg`),
        new Uint8Array(1024),
        { contentType: "image/jpeg" },
      );
    });
    await assertSucceeds(
      deleteObject(
        ref(storageAs(ATHLETE), `chatMedia/${CHAT_ID}/${ATHLETE}/borrable.jpg`),
      ),
    );
  });
});

describe("chatMedia — cap POR ARCHIVO", () => {
  it("DENIEGA una imagen de 16 MB (el cap es 15, y no tiene variante free)", async () => {
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await assertFails(imageOf(ATHLETE, "grande.jpg", 16 * MB));
  });

  it("deja pasar una imagen de 14 MB hasta con el paywall mordiendo", async () => {
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await assertSucceeds(imageOf(ATHLETE, "ok.jpg", 14 * MB));
  });

  it("DENIEGA un video de 26 MB al alumno enforced (su cap es 25)", async () => {
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await assertFails(videoOf(ATHLETE, "grande.mp4", 26 * MB));
  });

  it("deja pasar un video de 24 MB al alumno enforced", async () => {
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await assertSucceeds(videoOf(ATHLETE, "ok.mp4", 24 * MB));
  });

  // LA RAMA DEL TIER. Si el ternario se rompe y todos caen en el cap free, este
  // test es el que lo ve: el mismo archivo que el alumno no puede subir, el PF
  // sí.
  it("deja pasar ESE MISMO video de 26 MB a quien NO está enforced", async () => {
    await seedUser(TRAINER, { role: "trainer" });
    await assertSucceeds(videoOf(TRAINER, "ok.mp4", 26 * MB));
  });

  it("DENIEGA un video de 51 MB incluso a quien NO está enforced (techo estructural)", async () => {
    await seedUser(TRAINER, { role: "trainer" });
    await assertFails(videoOf(TRAINER, "enorme.mp4", 51 * MB));
  });
});

describe("chatMedia — tope de BYTES TOTALES", () => {
  it("acepta la subida que deja el total EXACTAMENTE en el tope", async () => {
    // La regla autoriza con `usage.bytes + size <= cap`. El archivo que clava
    // el total en 250 MB es legal; el siguiente ya no.
    await seedUser(ATHLETE, {
      athletePaywallEnforced: true,
      chatMediaUsage: { bytes: FREE_TOTAL - 1024, count: 9 },
    });
    await assertSucceeds(imageOf(ATHLETE, "justo.jpg", 1024));
  });

  it("DENIEGA la subida que CRUZA el tope aunque el archivo sea chiquito", async () => {
    await seedUser(ATHLETE, {
      athletePaywallEnforced: true,
      chatMediaUsage: { bytes: FREE_TOTAL - 1024, count: 9 },
    });
    await assertFails(imageOf(ATHLETE, "pasa.jpg", 2048));
  });

  it("DENIEGA cualquier subida con el cupo free ya agotado", async () => {
    await seedUser(ATHLETE, {
      athletePaywallEnforced: true,
      chatMediaUsage: { bytes: FREE_TOTAL, count: 20 },
    });
    await assertFails(imageOf(ATHLETE, "nada.jpg", 1024));
  });

  // LA RAMA DEL TIER, del lado del total. Los mismos 250 MB acumulados que
  // frenan al alumno no frenan al PF — que es lo que mantiene intacto el chat
  // del Coach en las dos puntas.
  it("deja pasar con 250 MB acumulados a quien NO está enforced", async () => {
    await seedUser(TRAINER, {
      role: "trainer",
      chatMediaUsage: { bytes: FREE_TOTAL, count: 20 },
    });
    await assertSucceeds(imageOf(TRAINER, "sigue.jpg", 1024));
  });

  it("DENIEGA a quien NO está enforced con 5 GB acumulados (techo estructural)", async () => {
    await seedUser(TRAINER, {
      role: "trainer",
      chatMediaUsage: { bytes: MAX_TOTAL, count: 900 },
    });
    await assertFails(imageOf(TRAINER, "nada.jpg", 1024));
  });

  it("trata el contador ausente como 0 y no como una denegación", async () => {
    // Un usuario que nunca subió media todavía no tiene el campo — la CF lo
    // escribe recién con el primer objeto. Si el default fuera otra cosa, la
    // PRIMERA subida de cada usuario del producto se caería.
    await seedUser(ATHLETE, { athletePaywallEnforced: true });
    await assertSucceeds(imageOf(ATHLETE, "primera.jpg", 1024));
  });
});

describe("chatMedia — fail-open sin doc de perfil", () => {
  // `firestore.get()` devuelve null si el doc no existe, y hay escrituras
  // legítimas de usuarios sin doc de perfil todavía. Sin doc ⇒ no enforced,
  // igual que `paywallEnforcedFor` en `firestore.rules`. Pero el TECHO
  // ESTRUCTURAL se aplica siempre: el fail-open afloja el tope del PAYWALL,
  // nunca el del PRODUCTO.
  it("deja pasar un video de 30 MB sin doc de perfil (cae en el techo, no en el free)", async () => {
    await assertSucceeds(videoOf(OTHER, "sindoc.mp4", 30 * MB));
  });

  it("DENIEGA un video de 51 MB sin doc de perfil — el techo sigue valiendo", async () => {
    await assertFails(videoOf(OTHER, "sindoc-enorme.mp4", 51 * MB));
  });
});
