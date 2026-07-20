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
