/**
 * Storage rules tests for the `avatars/{fileName}` block (#680 Slice E).
 *
 * ⚠️  COBERTURA DELIBERADAMENTE PARCIAL — leer `docs/security.md` §3.2 antes de
 * agregar casos acá. Este archivo pinea SOLO la mitad del bloque que ya está
 * decidida (la escritura). Dos celdas quedan sin test **a propósito**:
 *
 *  - `list`: hoy `allow read: if request.auth != null` deja que cualquier
 *    autenticado enumere `avatars/`, y como el nombre del archivo ES el uid,
 *    eso devuelve el padrón de uids con avatar. Es el leak QA-SEC-007 y se
 *    arregla en su propio PR. Testearlo ahora congelaría el status quo
 *    (§1.6 regla 1). Cuando QA-SEC-007 cierre, acá va el `assertFails` del
 *    `listAll`.
 *
 *  - `delete`: el bloque NO declara `allow delete`, así que cae en `write`,
 *    cuya condición dereferencia `request.resource.size` — que en un delete es
 *    null. Resultado medido: el borrado se deniega **hasta para el dueño**, y
 *    por "Null value error" en storage.rules:13, no por falta de permiso. Un
 *    test de "el ajeno no puede borrar" pasaría por el motivo equivocado, que
 *    §1.8 prohíbe explícitamente. Es QA-SEC-009.
 *
 * Lo que sí se pinea acá: el gate de escritura, que es owner-only, anclado,
 * limitado a imágenes, y correcto.
 *
 * El bound de 5 MB no se ejercita — empujar 5 MB por el emulador en cada corrida
 * es puro lastre de CI, y es el mismo idiom `request.resource.size` que ya
 * corre en los otros bloques.
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
import { getBytes, listAll, ref, uploadString } from "firebase/storage";

const PROJECT_ID = "treino-rules-test-avatars";
const RULES_PATH = path.resolve(__dirname, "../../../storage.rules");

const OWNER = "owneruid";
const OTHER = "otheruid";
// Prefijo estricto de OWNER: sirve para comprobar que `matches()` ancla.
const PREFIX_UID = "own";

const AVATAR_PATH = `avatars/${OWNER}.jpg`;

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
    await uploadString(ref(ctx.storage(), AVATAR_PATH), "seed-bytes", "raw", {
      contentType: "image/jpeg",
    });
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

describe("avatars/{fileName} — storage rules", () => {
  // --- escritura: owner-only, anclada, sólo imágenes ------------------------

  it("allows the owner to upload their own avatar", async () => {
    await assertSucceeds(
      uploadString(ref(storageAs(OWNER), `avatars/${OWNER}.png`), "img", "raw", {
        contentType: "image/png",
      })
    );
  });

  it("DENIES uploading over ANOTHER user's avatar", async () => {
    await assertFails(
      uploadString(ref(storageAs(OTHER), AVATAR_PATH), "img", "raw", {
        contentType: "image/jpeg",
      })
    );
  });

  it("DENIES a filename unrelated to the caller's uid", async () => {
    await assertFails(
      uploadString(ref(storageAs(OWNER), "avatars/mascota.jpg"), "img", "raw", {
        contentType: "image/jpeg",
      })
    );
  });

  it("DENIES a uid that is only a PREFIX of the target filename", async () => {
    // `fileName.matches(uid + '\\..+')` es full-match: 'own' no puede escribir
    // 'owneruid.jpg'. Si alguien cambiara matches() por un startsWith, esto
    // se pone rojo. Ver §1.7 — el mismo riesgo que el gate de athleteFiles.
    await assertFails(
      uploadString(ref(storageAs(PREFIX_UID), AVATAR_PATH), "img", "raw", {
        contentType: "image/jpeg",
      })
    );
    // Control positivo: su propio nombre sí entra.
    await assertSucceeds(
      uploadString(
        ref(storageAs(PREFIX_UID), `avatars/${PREFIX_UID}.jpg`),
        "img",
        "raw",
        { contentType: "image/jpeg" }
      )
    );
  });

  it("DENIES a file with no extension at all", async () => {
    await assertFails(
      uploadString(ref(storageAs(OWNER), `avatars/${OWNER}`), "img", "raw", {
        contentType: "image/jpeg",
      })
    );
  });

  it("DENIES a non-image contentType even for the owner", async () => {
    await assertFails(
      uploadString(ref(storageAs(OWNER), `avatars/${OWNER}.pdf`), "doc", "raw", {
        contentType: "application/pdf",
      })
    );
  });

  it("DENIES an unauthenticated upload", async () => {
    await assertFails(
      uploadString(ref(storageAs(null), AVATAR_PATH), "img", "raw", {
        contentType: "image/jpeg",
      })
    );
  });

  // --- lectura: sólo se pinea el piso (anónimo), NO el caso cruzado ---------

  it("DENIES an unauthenticated get", async () => {
    await assertFails(getBytes(ref(storageAs(null), AVATAR_PATH)));
  });

  it("DENIES an unauthenticated list of avatars/", async () => {
    // El caso AUTENTICADO está abierto y es QA-SEC-007 — no se testea acá.
    await assertFails(listAll(ref(storageAs(null), "avatars")));
  });
});
