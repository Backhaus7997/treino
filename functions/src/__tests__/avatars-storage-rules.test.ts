/**
 * Storage rules tests for the `avatars/{fileName}` block (#680 Slice E;
 * `list` cerrado por QA-SEC-007 / #764; `delete` arreglado por QA-SEC-009 /
 * #765).
 *
 * ⚠️  COBERTURA DELIBERADAMENTE PARCIAL — leer `docs/security.md` §3.2 antes de
 * agregar casos acá.
 *
 * `get` amplio NO se pinea: es un permiso deliberado (§3.2), y un
 * `assertSucceeds` ahí congelaría el status quo si mañana se decide apretarlo.
 * Sí se pinea el piso anónimo.
 *
 * Lo que sí se pinea acá:
 *
 *  - El gate de escritura: owner-only, anclado al uid, sólo imágenes.
 *  - El `list` cerrado (QA-SEC-007). El nombre del archivo ES el uid, así que
 *    enumerar `avatars/` devolvía el padrón de uids con avatar en una sola
 *    llamada.
 *  - El `delete`, en las DOS direcciones (QA-SEC-009). El positivo del dueño
 *    no es decorativo: hasta #765 el bloque no declaraba `allow delete`, el
 *    borrado caía en `write` —cuya condición dereferencia
 *    `request.resource.size`, null en un delete— y se denegaba hasta para el
 *    dueño con "Null value error". Sin ese positivo, el negativo del ajeno
 *    pasaría **por el motivo equivocado**, que es exactamente lo que §1.8
 *    prohíbe: era verdad por accidente, no por un gate de dueño.
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
import {
  deleteObject,
  getBytes,
  listAll,
  ref,
  uploadString,
} from "firebase/storage";

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

  // --- get: sólo se pinea el piso (anónimo), NO el caso cruzado ------------

  it("DENIES an unauthenticated get", async () => {
    await assertFails(getBytes(ref(storageAs(null), AVATAR_PATH)));
  });

  // --- list: cerrado incondicionalmente (QA-SEC-007) ------------------------

  it("DENIES listing avatars/ — no uid enumeration", async () => {
    // `avatars/{uid}.{ext}`: el nombre del archivo ES el uid, así que este
    // listado devolvía el padrón de uids con avatar. La regla es `if false`,
    // no owner-only — por eso el dueño también tiene que dar rojo. Ver
    // `docs/security.md` §3.2.
    await assertFails(listAll(ref(storageAs(OTHER), "avatars")));
    await assertFails(listAll(ref(storageAs(OWNER), "avatars")));
  });

  it("DENIES an unauthenticated list of avatars/", async () => {
    await assertFails(listAll(ref(storageAs(null), "avatars")));
  });

  // --- borrado: owner-only, y por el motivo correcto (QA-SEC-009) -----------

  it("allows the owner to delete their own avatar", async () => {
    // ESTE es el caso que estaba roto y el que sostiene a los negativos de
    // abajo. Sin `allow delete` propio el borrado caía en `write`, que
    // dereferencia `request.resource.size` — null en un delete — y explotaba
    // con "Null value error", denegando hasta al dueño. Si alguien borrara el
    // `allow delete` del bloque, este test se pone rojo y los negativos NO,
    // porque seguirían denegando por el crash. Ver `docs/security.md` §3.2.1.
    await assertSucceeds(deleteObject(ref(storageAs(OWNER), AVATAR_PATH)));
  });

  it("DENIES deleting ANOTHER user's avatar", async () => {
    await assertFails(deleteObject(ref(storageAs(OTHER), AVATAR_PATH)));
  });

  it("DENIES a delete from a uid that is only a PREFIX of the filename", async () => {
    // Mismo anclaje que el `write`: `fileName.matches(uid + '\\..+')` es
    // full-match, así que 'own' no puede borrar 'owneruid.jpg'. Si alguien
    // cambiara el gate por un startsWith, esto se pone rojo.
    await assertFails(deleteObject(ref(storageAs(PREFIX_UID), AVATAR_PATH)));
  });

  it("DENIES an unauthenticated delete", async () => {
    await assertFails(deleteObject(ref(storageAs(null), AVATAR_PATH)));
  });
});
