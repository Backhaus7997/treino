/**
 * delete-accounts.ts — borra cuentas puntuales (de prueba) por email, pasando
 * por LA MISMA cascada que el boton "Eliminar cuenta" de la app.
 *
 * ## Por que existe
 *
 * Borrar un usuario desde la consola de Firebase deja huerfano todo lo demas
 * (users, posts, vinculos, turnos, storage, suscripciones de Mercado Pago...).
 * Este CLI NO reimplementa nada: llama a `runDeleteAccount` de
 * `src/delete-account.ts`, o sea la cascada que corre el callable
 * `deleteAccount` — incluida la baja de MP FAIL-CLOSED (si MP no responde, la
 * cuenta NO se toca), el `audit_log/{uid}` y el borrado de Auth AL FINAL.
 *
 * ## Que NO es
 *
 * No es una Cloud Function: vive en `functions/scripts/`, que `tsconfig.json`
 * (`include: ["src"]`) no compila a `lib/` y `src/index.ts` no exporta. No se
 * despliega. Lo chequea `npm run typecheck:scripts` (CI) y lo cubre
 * `src/__tests__/delete-accounts-cli.test.ts`.
 *
 * ## Seguridad
 *
 * 🚨 `--apply` BORRA DE VERDAD y `treino-dev` ES PRODUCCION (AGENTS.md ->
 * Entornos). Auth y Storage NO tienen backup: lo que se borra ahi no vuelve.
 *
 *  - DRY-RUN por default: sin `--apply` no escribe nada.
 *  - Contra un proyecto real exige `--project=<id>` y que COINCIDA con la
 *    identidad de la credencial (`$TREINO_SA_KEY`, ver scripts/lib/admin.js).
 *  - Se NIEGA a borrar las cuentas operativas del dueno (ver `esCuentaOperativa`).
 *    No hay flag para saltearlo: si hace falta, se borra a mano.
 *  - Se NIEGA a borrar entrenadores (`role == 'trainer'`) sin `--allow-trainers`:
 *    su cascada avisa a los alumnos vinculados.
 *  - Secuencial; una excepcion en una cuenta se reporta y sigue con la proxima.
 *    Sale con codigo != 0 si alguna cuenta pedida no quedo borrada del todo.
 *  - Un resultado `partial` lo reintenta `retryPartialDeletions` (retention/).
 *
 * ## Uso (desde functions/)
 *
 *   # dry-run (default):
 *   TREINO_SA_KEY="$HOME/.config/treino/sa-key.json" \
 *     npx --yes ts-node scripts/delete-accounts.ts --project treino-dev \
 *     --emails=a@example.com,b@example.com
 *
 *   # borrar de verdad: el mismo comando + --apply
 *
 * Detalle y variantes en scripts/README.md.
 */

import * as fs from "fs";
import { App, cert, initializeApp } from "firebase-admin/app";
import { getAuth, UserRecord } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";

import { runDeleteAccount } from "../src/delete-account";
import { DeleteAccountResponse } from "../src/types";

/* eslint-disable @typescript-eslint/no-require-imports, @typescript-eslint/no-explicit-any */
// Las reglas de credenciales y de produccion viven en `scripts/lib/` (JS, sin
// dependencias): se REUSAN, no se copian, para que este CLI no tenga su propia
// idea de "que es produccion".
const { ErrorDeCredencial, resolverContexto } = require("../../scripts/lib/credenciales");
const { bannerDeProduccion } = require("../../scripts/lib/firebase_projects");
const { contraEmuladorDe } = require("../../scripts/lib/target_project");
/* eslint-enable @typescript-eslint/no-require-imports, @typescript-eslint/no-explicit-any */

/** Proveedor que queda en `audit_log/{uid}.provider`: distingue el borrado admin del de la app. */
const PROVIDER_ADMIN = "admin-cli";

// ── Denylist: cuentas operativas del dueno ───────────────────────────────

const OPERATIVAS_EXACTAS = [
  "treino@gettreino.com",
  "treinosupport@gettreino.com",
  "treinopf@gmail.com",
  "martin.backhaus@code-assurance.com",
];

/**
 * ¿Es una cuenta operativa del dueno? Si si, el CLI se niega a borrarla.
 *
 * Patrones: las cuatro exactas de arriba, `testplaystore*@gmail.com`, todo
 * gmail con alias (`algo+x@gmail.com`) y todo `@privaterelay.appleid.com`
 * (el email oculto de Sign in with Apple, que no se puede reconocer por nombre).
 */
export function esCuentaOperativa(email: string): boolean {
  const e = email.trim().toLowerCase();
  if (OPERATIVAS_EXACTAS.includes(e)) return true;
  const at = e.lastIndexOf("@");
  if (at < 0) return false;
  const local = e.slice(0, at);
  const dominio = e.slice(at + 1);
  if (dominio === "privaterelay.appleid.com") return true;
  if (dominio === "gmail.com") {
    return local.startsWith("testplaystore") || local.includes("+");
  }
  return false;
}

// ── Argumentos ───────────────────────────────────────────────────────────

export interface Opciones {
  emails: string[];
  file?: string | null;
  project?: string | null;
  apply: boolean;
  allowTrainers: boolean;
}

/** Normaliza (trim + minusculas), sin vacios ni duplicados. */
function normalizar(emails: string[]): string[] {
  return [...new Set(emails.map((e) => e.trim().toLowerCase()).filter(Boolean))];
}

/**
 * Acepta `--flag=valor` y `--flag valor` para los flags con valor. Los
 * booleanos (`--apply`, `--allow-trainers`, `--dry-run`) aceptan SOLO la forma
 * desnuda: `--apply=false` tira en vez de leerse como `--apply` (borrado
 * irreversible cuando se pidio lo contrario). Flag desconocida => tira (en vez
 * de ignorarla): `--force-operational` o el typo `--aply` no deben pasar.
 */
export function parseArgs(argv: string[]): Opciones {
  const o: Opciones = { emails: [], file: null, project: null, apply: false, allowTrainers: false };
  const conValor = new Set(["--emails", "--file", "--project"]);
  const BOOLEANOS = new Set(["--apply", "--dry-run", "--allow-trainers"]);
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const [nombre, inline] = arg.split(/=(.*)/s, 2);
    if (BOOLEANOS.has(nombre)) {
      if (inline !== undefined) {
        throw new Error(
          `${nombre} no acepta valor (recibi "${arg}"). Usalo desnudo: ${nombre}.`,
        );
      }
      if (nombre === "--apply") o.apply = true;
      else if (nombre === "--dry-run") o.apply = false;
      else o.allowTrainers = true;
    } else if (conValor.has(nombre)) {
      const valor = inline ?? argv[++i];
      if (valor === undefined || valor.startsWith("--")) {
        throw new Error(`${nombre} necesita un valor.`);
      }
      if (nombre === "--emails") o.emails.push(...valor.split(","));
      else if (nombre === "--file") o.file = valor;
      else o.project = valor;
    } else {
      throw new Error(`Flag desconocida: ${arg}`);
    }
  }
  o.emails = normalizar(o.emails);
  if (o.emails.length === 0 && !o.file) {
    throw new Error("Pasa --emails=a@b.com,c@d.com o --file=<ruta> (un email por linea).");
  }
  return o;
}

/** Une `--emails` con las lineas de `--file`. */
export function leerEmails(o: Pick<Opciones, "emails" | "file">): string[] {
  const deArchivo = o.file ? fs.readFileSync(o.file, "utf8").split(/\r?\n/) : [];
  return normalizar([...o.emails, ...deArchivo]);
}

// ── Guard de destino ─────────────────────────────────────────────────────

export interface Destino {
  ok: boolean;
  error?: string;
  projectId?: string;
  banner?: string | null;
}

/**
 * Compuerta de proyecto. `contexto` es lo que devuelve `resolverContexto`.
 * Contra un proyecto real, `--project` es OBLIGATORIO y tiene que coincidir con
 * la identidad de la credencial: el comando no puede decir una cosa y apuntar a
 * otra.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function validarDestino(contexto: any, projectFlag: string | null | undefined): Destino {
  if (contexto.modo === "emulador") {
    return { ok: true, projectId: projectFlag || contexto.projectId, banner: null };
  }
  const real: string | undefined =
    contexto.proyectoDeLaIdentidad || contexto.credencial?.project_id || undefined;
  if (!real) {
    return { ok: false, error: "No pude determinar el proyecto de la credencial. Abortando." };
  }
  if (!projectFlag) {
    return {
      ok: false,
      error: `Falta --project. La credencial apunta a "${real}": escribilo explicito (--project ${real}).`,
    };
  }
  if (projectFlag.trim().toLowerCase() !== real.trim().toLowerCase()) {
    return {
      ok: false,
      error: `--project=${projectFlag} no coincide con la identidad de la credencial (${real}). Abortando.`,
    };
  }
  return { ok: true, projectId: real, banner: bannerDeProduccion(real) };
}

// ── Nucleo ───────────────────────────────────────────────────────────────

export type Estado =
  | "dry-run"
  | "success"
  | "partial"
  | "fallo"
  | "rechazada"
  | "no-encontrada"
  | "error";

export interface Resultado {
  email: string;
  uid?: string;
  estado: Estado;
  /** Mensaje del error cuando `estado == "error"`. */
  detalle?: string;
}

export type Runner = (
  app: App,
  uid: string,
  provider: string,
) => Promise<DeleteAccountResponse>;

type Log = (linea: string) => void;

const fecha = (s?: string) => s ?? "(nunca)";

/**
 * Resuelve cada email, imprime la ficha y —con `apply`— borra, de a una.
 * `runner` es inyectable solo para los tests; en produccion es `runDeleteAccount`.
 */
export async function ejecutar(
  opciones: Pick<Opciones, "emails" | "apply" | "allowTrainers"> & { file?: string | null },
  app: App,
  log: Log = console.log,
  runner: Runner = runDeleteAccount,
): Promise<{ exitCode: number; resultados: Resultado[] }> {
  const emails = leerEmails(opciones);
  const modo = opciones.apply ? "APPLY (borra de verdad)" : "DRY-RUN (no escribe nada)";
  log(`\nModo: ${modo} — ${emails.length} email(s)\n`);

  const resultados: Resultado[] = [];
  const vistos = new Set<string>();

  for (const email of emails) {
    try {
      let user: UserRecord;
      try {
        user = await getAuth(app).getUserByEmail(email);
      } catch (err) {
        if ((err as { code?: string }).code === "auth/user-not-found") {
          log(`- NO ENCONTRADO ${email}: no hay usuario de Auth con ese email.`);
          resultados.push({ email, estado: "no-encontrada" });
        } else {
          log(`- ERROR ${email}: no pude consultar Auth: ${(err as Error).message}`);
          resultados.push({ email, estado: "error", detalle: (err as Error).message });
        }
        continue;
      }
      if (vistos.has(user.uid)) continue;
      vistos.add(user.uid);

      const snap = await getFirestore(app).collection("users").doc(user.uid).get();
      const rol = snap.exists ? String(snap.data()?.role ?? "(sin role)") : "(sin doc users)";
      log(
        [
          `- ${email}`,
          `    uid:        ${user.uid}`,
          `    providers:  ${user.providerData.map((p) => p.providerId).join(", ") || "(ninguno)"}`,
          `    createdAt:  ${fecha(user.metadata.creationTime)}`,
          `    lastSignIn: ${fecha(user.metadata.lastSignInTime)}`,
          `    users doc:  ${snap.exists ? "existe" : "NO existe"}   role: ${rol}`,
        ].join("\n"),
      );

      if (esCuentaOperativa(email)) {
        log("    RECHAZADA: es una cuenta operativa del dueno. Este CLI no la borra.");
        resultados.push({ email, uid: user.uid, estado: "rechazada" });
        continue;
      }
      if (rol === "trainer" && !opciones.allowTrainers) {
        log(
          "    RECHAZADA: es un entrenador; su cascada notifica a los alumnos vinculados. " +
            "Si es lo que queres, repetilo con --allow-trainers.",
        );
        resultados.push({ email, uid: user.uid, estado: "rechazada" });
        continue;
      }
      if (!opciones.apply) {
        log("    dry-run: se borraria con --apply.");
        resultados.push({ email, uid: user.uid, estado: "dry-run" });
        continue;
      }

      try {
        const r = await runner(app, user.uid, PROVIDER_ADMIN);
        if (r.status === "success") {
          log(`    SUCCESS: borrada (${r.deletedCollections.join(", ")}).`);
          resultados.push({ email, uid: user.uid, estado: "success" });
        } else {
          log(
            `    PARTIAL: quedaron errores: ${r.errors.join(" | ")}\n` +
              "    La Auth/datos que falten los reintenta retryPartialDeletions (audit_log/{uid}).",
          );
          resultados.push({ email, uid: user.uid, estado: "partial" });
        }
      } catch (err) {
        log(
          `    FALLO ${user.uid}: la cascada tiro una excepcion: ${(err as Error).message}\n` +
            "    La cuenta puede haber quedado intacta (MP fail-closed) o a medias: revisa audit_log/{uid}.",
        );
        resultados.push({ email, uid: user.uid, estado: "fallo" });
      }
    } catch (err) {
      // Auth ok pero Firestore (u otra cosa) tiro: esta cuenta falla, las demas siguen.
      const msg = (err as Error).message;
      log(`- ERROR ${email}: no pude procesar la cuenta: ${msg}`);
      resultados.push({ email, estado: "error", detalle: msg });
    }
  }

  const cuenta = (e: Estado) => resultados.filter((r) => r.estado === e).length;
  log(
    `\nResumen: ${cuenta("success")} borradas, ${cuenta("partial")} partial, ${cuenta("fallo")} fallaron, ` +
      `${cuenta("rechazada")} rechazadas, ${cuenta("no-encontrada") + cuenta("error")} sin resolver, ` +
      `${cuenta("dry-run")} solo dry-run.`,
  );
  const conError = resultados.filter((r) => r.estado === "error");
  if (conError.length > 0) {
    log(
      "Con ERROR (no se pudieron procesar): " +
        conError.map((r) => `${r.email} (${r.detalle ?? "sin detalle"})`).join("; "),
    );
  }
  if (!opciones.apply) log("Nada se escribio. Para borrar: repeti el comando con --apply.");

  const todasBorradas = resultados.length > 0 && resultados.every((r) => r.estado === "success");
  return { exitCode: opciones.apply && !todasBorradas ? 1 : 0, resultados };
}

// ── Entrypoint ───────────────────────────────────────────────────────────

export async function main(argv: string[], env: NodeJS.ProcessEnv = process.env): Promise<number> {
  let opciones: Opciones;
  try {
    opciones = parseArgs(argv);
  } catch (err) {
    console.error((err as Error).message);
    return 2;
  }

  let contexto;
  try {
    contexto = resolverContexto({
      env,
      projectIdEmulador: env.GCLOUD_PROJECT || "demo-delete-accounts",
    });
  } catch (err) {
    if (!(err instanceof ErrorDeCredencial)) throw err;
    console.error((err as Error).message);
    return 1;
  }

  // `resolverContexto` da "emulador" con solo Firestore desviado. Este CLI
  // ademas toca Auth y Storage: si alguno va a la nube, es produccion disfrazada.
  if (contexto.modo === "emulador" && !contraEmuladorDe(["firestore", "auth", "storage"], env)) {
    console.error(
      "Emulador incompleto: este CLI usa Firestore, Auth y Storage y los tres deben estar " +
        "desviados (FIRESTORE_EMULATOR_HOST, FIREBASE_AUTH_EMULATOR_HOST, FIREBASE_STORAGE_EMULATOR_HOST).",
    );
    return 1;
  }

  const destino = validarDestino(contexto, opciones.project);
  if (!destino.ok) {
    console.error(destino.error);
    return 1;
  }
  if (destino.banner) console.error(destino.banner);
  const projectId = destino.projectId as string;
  console.log(`Proyecto: ${projectId}${contexto.modo === "emulador" ? " (EMULADOR)" : ""}`);

  // Como `lib/admin.js`: el resto del proceso hereda la ruta ya validada.
  if (contexto.modo === "credencial") env.GOOGLE_APPLICATION_CREDENTIALS = contexto.ruta;

  const app = initializeApp({
    ...(contexto.modo === "credencial" ? { credential: cert(contexto.credencial) } : {}),
    projectId,
    storageBucket: contexto.modo === "emulador" ? `${projectId}.appspot.com` : `${projectId}.firebasestorage.app`,
  });

  const { exitCode } = await ejecutar(opciones, app);
  return exitCode;
}

if (require.main === module) {
  main(process.argv.slice(2)).then(
    (code) => process.exit(code),
    (err) => {
      console.error("Error inesperado:", err);
      process.exit(1);
    },
  );
}
