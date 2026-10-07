/**
 * delete-accounts-cli.test.ts — el CLI admin `functions/scripts/delete-accounts.ts`.
 *
 * EMULADOR (Firestore + Auth + Storage):
 *
 *   firebase emulators:exec --only firestore,auth,storage --project demo-del \
 *     "npm --prefix functions test -- --runInBand delete-accounts-cli"
 *
 * Lo que prueba: que el CLI es DRY-RUN por default, que con `--apply` llama a la
 * cascada REAL (`runDeleteAccount`) y que sus compuertas —denylist operativa,
 * entrenadores, email inexistente, excepcion por cuenta— frenan ANTES de tocar
 * nada. La cascada en si ya la cubren los tests de delete-account.
 */

process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";
process.env.FIREBASE_STORAGE_EMULATOR_HOST ??= "127.0.0.1:9199";
process.env.GCLOUD_PROJECT ??= "demo-del";

import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";

import {
  ejecutar,
  esCuentaOperativa,
  leerEmails,
  parseArgs,
  validarDestino,
} from "../../scripts/delete-accounts";

let app: App;

beforeAll(() => {
  app = initializeApp(
    { projectId: "demo-del", storageBucket: "demo-del.appspot.com" },
    "delete-accounts-cli-test",
  );
});

afterAll(async () => {
  await deleteApp(app);
});

const db = () => getFirestore(app);
const hayAuth = (uid: string) =>
  getAuth(app).getUser(uid).then(() => true, () => false);
const hayDoc = async (col: string, id: string) =>
  (await db().collection(col).doc(id).get()).exists;

function salida() {
  const lineas: string[] = [];
  return { lineas, log: (l: string) => lineas.push(l), texto: () => lineas.join("\n") };
}

async function sembrar(uid: string, email: string, role: string | null = "athlete") {
  await getAuth(app).createUser({ uid, email, password: "secreto-de-test-1" });
  if (role !== null) await db().collection("users").doc(uid).set({ role, email });
}

async function limpiar(...uids: string[]) {
  for (const uid of uids) {
    await getAuth(app).deleteUser(uid).catch(() => undefined);
    await db().collection("users").doc(uid).delete();
    await db().collection("audit_log").doc(uid).delete();
  }
}

describe("esCuentaOperativa (denylist)", () => {
  it.each([
    "treino@gettreino.com",
    "TreinoSupport@gettreino.com",
    "treinopf@gmail.com",
    "testplaystore@gmail.com",
    "testplaystore7@gmail.com",
    "martin.backhaus@code-assurance.com",
    "martin+qa@gmail.com",
    "abc123@privaterelay.appleid.com",
  ])("%s es operativa", (email) => {
    expect(esCuentaOperativa(email)).toBe(true);
  });

  it.each(["qa-uno@example.com", "alguien@gmail.com", "x@gettreino.com.ar", "plus+a@yahoo.com"])(
    "%s NO es operativa",
    (email) => {
      expect(esCuentaOperativa(email)).toBe(false);
    },
  );
});

describe("parseArgs / leerEmails", () => {
  it("es dry-run salvo --apply", () => {
    expect(parseArgs(["--emails=a@b.com"]).apply).toBe(false);
    expect(parseArgs(["--emails=a@b.com", "--apply"]).apply).toBe(true);
  });

  it("parsea --emails, --project y --allow-trainers", () => {
    const o = parseArgs(["--emails=a@b.com, C@D.com", "--project=treino-dev", "--allow-trainers"]);
    expect(o.emails).toEqual(["a@b.com", "c@d.com"]);
    expect(o.project).toBe("treino-dev");
    expect(o.allowTrainers).toBe(true);
  });

  it("rechaza flags desconocidas (--force-operational NO existe)", () => {
    expect(() => parseArgs(["--emails=a@b.com", "--force-operational"])).toThrow(/desconocida/i);
  });

  it("exige --emails o --file", () => {
    expect(() => parseArgs([])).toThrow(/--emails|--file/);
  });

  it("lee un archivo de una direccion por linea, sin vacias ni duplicadas", () => {
    const f = path.join(os.tmpdir(), `del-emails-${process.pid}.txt`);
    fs.writeFileSync(f, "A@b.com\n\n  c@d.com  \na@b.com\n");
    try {
      expect(leerEmails({ emails: [], file: f })).toEqual(["a@b.com", "c@d.com"]);
    } finally {
      fs.unlinkSync(f);
    }
  });
});

describe("validarDestino (guard de proyecto)", () => {
  const credencial = (id: string) => ({
    modo: "credencial",
    produccion: id === "treino-dev",
    credencial: { project_id: id },
    proyectoDeLaIdentidad: id,
  });

  it("emulador: pasa sin --project", () => {
    expect(validarDestino({ modo: "emulador", projectId: "demo-del" }, null).ok).toBe(true);
  });

  it("credencial real sin --project: se niega", () => {
    const r = validarDestino(credencial("treino-dev"), null);
    expect(r.ok).toBe(false);
    expect(r.error).toMatch(/--project/);
  });

  it("credencial de otro proyecto que --project: se niega", () => {
    const r = validarDestino(credencial("treino-dev"), "otro-proyecto");
    expect(r.ok).toBe(false);
    expect(r.error).toMatch(/no coincide/);
  });

  it("credencial y --project coinciden: pasa y avisa produccion", () => {
    const r = validarDestino(credencial("treino-dev"), "treino-dev");
    expect(r.ok).toBe(true);
    expect(r.projectId).toBe("treino-dev");
    expect(r.banner).toMatch(/PRODUCTION/);
  });
});

describe("ejecutar (contra el emulador)", () => {
  const base = { allowTrainers: false };

  it("DRY-RUN: informa y no escribe nada", async () => {
    await sembrar("cli-dry", "cli-dry@example.com");
    try {
      const o = salida();
      const r = await ejecutar({ ...base, emails: ["cli-dry@example.com"], apply: false }, app, o.log);
      expect(r.exitCode).toBe(0);
      expect(o.texto()).toContain("cli-dry");
      expect(o.texto()).toContain("cli-dry@example.com");
      expect(o.texto()).toMatch(/DRY-RUN/);
      expect(await hayAuth("cli-dry")).toBe(true);
      expect(await hayDoc("users", "cli-dry")).toBe(true);
      expect(await hayDoc("audit_log", "cli-dry")).toBe(false);
    } finally {
      await limpiar("cli-dry");
    }
  });

  it("APPLY: borra el doc users y el usuario de Auth, y deja audit_log", async () => {
    await sembrar("cli-apply", "cli-apply@example.com");
    try {
      const o = salida();
      const r = await ejecutar({ ...base, emails: ["cli-apply@example.com"], apply: true }, app, o.log);
      expect(r.exitCode).toBe(0);
      expect(r.resultados[0]).toMatchObject({ uid: "cli-apply", estado: "success" });
      expect(await hayAuth("cli-apply")).toBe(false);
      expect(await hayDoc("users", "cli-apply")).toBe(false);
      const audit = await db().collection("audit_log").doc("cli-apply").get();
      expect(audit.data()?.status).toBe("success");
    } finally {
      await limpiar("cli-apply");
    }
  });

  it("email inexistente: se reporta y, con --apply, el exit es distinto de 0", async () => {
    const o = salida();
    const r = await ejecutar({ ...base, emails: ["no-existe@example.com"], apply: true }, app, o.log);
    expect(r.exitCode).not.toBe(0);
    expect(o.texto()).toMatch(/NO ENCONTRADO.*no-existe@example\.com/);
  });

  it("denylist: rechaza la cuenta operativa aun con --apply y no toca nada", async () => {
    await sembrar("cli-op", "treinopf@gmail.com");
    await sembrar("cli-plus", "martin+borrar@gmail.com");
    try {
      const o = salida();
      const r = await ejecutar(
        { ...base, emails: ["treinopf@gmail.com", "martin+borrar@gmail.com"], apply: true },
        app,
        o.log,
      );
      expect(r.exitCode).not.toBe(0);
      expect(o.texto()).toMatch(/RECHAZADA.*operativa/i);
      for (const uid of ["cli-op", "cli-plus"]) {
        expect(await hayAuth(uid)).toBe(true);
        expect(await hayDoc("users", uid)).toBe(true);
        expect(await hayDoc("audit_log", uid)).toBe(false);
      }
    } finally {
      await limpiar("cli-op", "cli-plus");
    }
  });

  it("entrenador: rechazado sin --allow-trainers, borrado con el", async () => {
    await sembrar("cli-pf", "cli-pf@example.com", "trainer");
    try {
      const o = salida();
      const sin = await ejecutar({ ...base, emails: ["cli-pf@example.com"], apply: true }, app, o.log);
      expect(sin.exitCode).not.toBe(0);
      expect(o.texto()).toMatch(/RECHAZADA.*entrenador/i);
      expect(await hayAuth("cli-pf")).toBe(true);
      expect(await hayDoc("users", "cli-pf")).toBe(true);

      const con = await ejecutar(
        { emails: ["cli-pf@example.com"], apply: true, allowTrainers: true },
        app,
        salida().log,
      );
      expect(con.exitCode).toBe(0);
      expect(await hayAuth("cli-pf")).toBe(false);
      expect(await hayDoc("users", "cli-pf")).toBe(false);
    } finally {
      await limpiar("cli-pf");
    }
  });

  it("una excepcion en una cuenta se reporta, sigue con la siguiente y el exit es 1", async () => {
    await sembrar("cli-boom", "cli-boom@example.com");
    await sembrar("cli-ok", "cli-ok@example.com");
    try {
      const o = salida();
      const runner = jest.fn(async (a: App, uid: string, provider: string) => {
        if (uid === "cli-boom") throw new Error("MP no responde");
        const { runDeleteAccount } = await import("../delete-account");
        return runDeleteAccount(a, uid, provider);
      });
      const r = await ejecutar(
        { ...base, emails: ["cli-boom@example.com", "cli-ok@example.com"], apply: true },
        app,
        o.log,
        runner,
      );
      expect(r.exitCode).toBe(1);
      expect(runner).toHaveBeenCalledTimes(2);
      expect(o.texto()).toMatch(/FALLO.*cli-boom.*MP no responde/s);
      expect(await hayAuth("cli-boom")).toBe(true);
      expect(await hayAuth("cli-ok")).toBe(false);
    } finally {
      await limpiar("cli-boom", "cli-ok");
    }
  });

  it("resultado partial: exit 1 y avisa que lo reintenta retryPartialDeletions", async () => {
    await sembrar("cli-partial", "cli-partial@example.com");
    try {
      const o = salida();
      const runner = jest.fn(async () => ({
        status: "partial" as const,
        deletedCollections: ["users"],
        errors: ["storage: boom"],
      }));
      const r = await ejecutar(
        { ...base, emails: ["cli-partial@example.com"], apply: true },
        app,
        o.log,
        runner,
      );
      expect(r.exitCode).toBe(1);
      expect(o.texto()).toMatch(/PARTIAL/);
      expect(o.texto()).toMatch(/retryPartialDeletions/);
      expect(o.texto()).toContain("storage: boom");
    } finally {
      await limpiar("cli-partial");
    }
  });
});
