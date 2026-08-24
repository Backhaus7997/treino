/**
 * QA-SEC-006 — static guard: every DEPLOYED callable must enforce App Check.
 *
 * App Check enforcement is not practically testable via firebase-functions-test
 * (it lives in the Functions transport layer, not the handler), so this is a
 * source-level assertion: each callable exported from index.ts must pass
 * `enforceAppCheck: true` in its onCall options. It fails loudly if a callable
 * ships — or is edited back — without attestation.
 *
 * resolveGymPlace is intentionally excluded: it is shelved in index.ts (not
 * exported / not deployed), so it has no attack surface.
 */
import { readFileSync } from "fs";
import { join } from "path";

const SRC = join(__dirname, "..");

const DEPLOYED_CALLABLES = [
  { file: "delete-account.ts", symbol: "deleteAccountHandler" },
  { file: "add-alias.ts", symbol: "addAlias" },
];

describe("QA-SEC-006: App Check enforcement on deployed callables", () => {
  it.each(DEPLOYED_CALLABLES)(
    "$symbol ($file) sets enforceAppCheck: true",
    ({ file }) => {
      const src = readFileSync(join(SRC, file), "utf8");
      expect(src).toMatch(/enforceAppCheck:\s*true/);
    },
  );

  // Los callables de auth estan shelved hasta que el dominio del remitente
  // este verificado en Resend. `requestPasswordReset` es el UNICO callable del
  // repo invocable sin sesion, y cada llamada le manda un mail a un tercero:
  // sin atestacion es un amplificador de spam apuntable. Este test lo cubre en
  // los dos estados — shelved hoy, y con App Check obligatorio el dia que se
  // exporte — asi que activarlo sin atestacion no puede pasar en silencio.
  it.each(["requestPasswordReset", "requestEmailVerification"])(
    "%s enforces App Check whenever it is exported",
    (symbol) => {
      const index = readFileSync(join(SRC, "index.ts"), "utf8");
      const exported = new RegExp(
        `^\\s*export\\s*\\{[^}]*\\b${symbol}\\b`,
        "m",
      ).test(index);

      // Shelved o no, el archivo ya tiene que declarar la atestacion.
      const src = readFileSync(join(SRC, "auth/request-auth-email.ts"), "utf8");
      expect(src).toMatch(/enforceAppCheck:\s*true/);

      if (exported) {
        // Al exportarse pasa a ser un callable desplegado: se suma al
        // inventario de DEPLOYED_CALLABLES de arriba.
        expect(src).toMatch(
          new RegExp(`export const ${symbol} = functions.onCall`),
        );
      }
    },
  );

  it("resolveGymPlace stays shelved (or, if un-shelved, must enforce App Check)", () => {
    const index = readFileSync(join(SRC, "index.ts"), "utf8");
    const exported = /^\s*export\s*\{\s*resolveGymPlace/m.test(index);
    if (exported) {
      const src = readFileSync(join(SRC, "places-search.ts"), "utf8");
      expect(src).toMatch(/enforceAppCheck:\s*true/);
    } else {
      // Still shelved — nothing to enforce.
      expect(exported).toBe(false);
    }
  });
});
