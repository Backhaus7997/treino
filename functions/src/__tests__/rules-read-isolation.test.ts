/**
 * rules-read-isolation.test.ts — static scanner over `firestore.rules` that
 * freezes WHICH rule clauses are allowed to know about the paywall.
 *
 * LOCAL — no emulator. Reads the rules file as TEXT and parses it, so it runs
 * everywhere `jest` runs (Java version irrelevant).
 *
 * WHY THIS EXISTS
 * The paywall restricts what a TRAINER may WRITE about a blocked athlete. The
 * product decision is absolute: the athlete never loses anything. The
 * catastrophic failure mode is someone wiring the block check into a READ
 * clause and taking the routine away from the athlete.
 *
 * A grep cannot catch that, for the two reasons this file is built around:
 *
 *  1. SHARED HELPERS. `reactionPostReadable()` (firestore.rules ~675-697)
 *     already serves `allow read` AND `allow create, update` at once — live
 *     precedent, not a hypothetical. A new helper that mixes the same way
 *     would leak a block check into the read path with nothing at the read
 *     clause itself to see. So this scanner walks the helper call graph and
 *     takes its TRANSITIVE closure before deciding what a clause "knows".
 *
 *  2. PROXIMITY. The `allow read` of routines (firestore.rules ~165-166)
 *     ALREADY does get(userPublicProfiles/$(resource.data.assignedBy)) — the
 *     rule that decides whether the athlete sees their routine already reads
 *     a PF document, with `assignedBy` in hand. Reading `blockedAthleteIds`
 *     off that same doc is one line away. That is the exact spot where the
 *     mistake writes itself.
 *
 * WHAT IT ASSERTS — three things, deliberately separate:
 *   1. The frozen INVENTORY (§5): the exact set of clauses whose transitive
 *      closure mentions a paywall token. A new clause touching one of them
 *      turns this red and forces a deliberate inventory update.
 *   2. The SYNTACTIC INVARIANT (§6): no clause carrying a read verb may ever
 *      be in that set.
 *   3. The SHORT-CIRCUIT ORDER (§7) of the three read clauses that reach
 *      paywall-written DATA without ever naming the paywall.
 *
 * WHAT IT DOES **NOT** ASSERT — read this before trusting a green.
 *
 * This is a TEXT scanner, so §6 proves a SYNTACTIC property: no read clause in
 * firestore.rules NAMES the paywall, directly or through a helper. It does NOT
 * prove the semantic property that no data written by the paywall pipeline can
 * affect a read. Those are different statements, and the gap between them is a
 * live path in this codebase:
 *
 *   the entitlement sweep writes `trainer_links`
 *     -> syncSessionShareOnTrainerLink (functions/src/sync-session-share.ts)
 *        fires on that write and sets/deletes `session_shares/{athleteId}`
 *     -> and `session_shares` is read by three clauses:
 *        firestore.rules:1471 (sessions), :1485 (setLogs), :1723 (measurements)
 *
 * `session_shares` is deliberately NOT in PAYWALL_TOKENS, and that is a
 * decision, not an oversight. Adding it would paint those three clauses red
 * while all three are correct: in every one of them the OWNER branch comes
 * FIRST and `||` short-circuits, so the athlete reading their own data never
 * reaches the get(). A red that has to be suppressed teaches nothing, and a
 * suppressed assert is worth nothing. §7 pins the fact that actually protects
 * the athlete there. The guard on what that CF may WRITE is not this file's
 * job either — it lives in sync-session-share.ts and its own test.
 *
 * PARSER STANCE: loud over lenient. Every construct the file can contain is
 * enumerated; anything unrecognized throws with a line number instead of being
 * skipped. A scanner that produces false negatives is worse than no scanner —
 * it buys false confidence. The sanity block below cross-checks the parser
 * against an independent line count so a parser that silently returns nothing
 * cannot pass the other assertions.
 */

import * as fs from "fs";
import * as path from "path";

const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");
const RAW_RULES = fs.readFileSync(RULES_PATH, "utf8");

/**
 * Tokens that mean "this clause knows about the paywall block state".
 *
 * `blockedAthleteIds` was listed BEFORE it existed in firestore.rules, because
 * the denormalized-list shape is the most likely way a future enforcement
 * lands and the scanner has to be armed first. As of paywall slice 5 it is in
 * the file — pinned equal-to-existing on `users/{uid}` update and refused
 * outright on create, both WRITE clauses, both frozen below. Arming it early
 * paid off: the entry landed in the inventory the moment the clause appeared,
 * instead of someone having to remember.
 *
 * `acceptedAt` is listed for the same reason and is already in the file
 * (trainer_links create + update). It is paywall-load-bearing by definition:
 * it is the ONLY ordering key of reconcileEntitlements, so it decides WHICH
 * athlete loses the slot when a trainer goes over the cap. If it ever shows up
 * in a read/get/list clause, §6 must go red.
 */
const PAYWALL_TOKENS = [
  "trainer_links",
  "entitlement",
  "acceptedAt",
  "blockedAthleteIds",
  "blockedAt",
  "blockedReason",
] as const;

const KNOWN_VERBS = ["read", "get", "list", "write", "create", "update", "delete"] as const;

/** `write` is create+update+delete — it is NOT a read verb. */
const READ_VERBS = ["read", "get", "list"] as const;

/** Nested matches concatenate; this prefix is the document root, not a collection. */
const DOCUMENTS_ROOT = "/databases/{database}/documents";

interface RuleFunction {
  readonly name: string;
  readonly body: string;
  readonly line: number;
}

interface AllowClause {
  /** Match path the clause lives under, document-root prefix removed. */
  readonly path: string;
  readonly verbs: readonly string[];
  /** The `if ...` expression, comments already stripped. */
  readonly expr: string;
  readonly line: number;
}

interface RulesModel {
  readonly stripped: string;
  readonly functions: ReadonlyMap<string, RuleFunction>;
  readonly clauses: readonly AllowClause[];
  /** Stable per-clause identity, index-aligned with `clauses`. */
  readonly ids: readonly string[];
}

// ---------------------------------------------------------------------------
// 1. Comment stripping — runs FIRST, and it carries real weight.
// ---------------------------------------------------------------------------
// firestore.rules mentions `trainer_links` in PROSE on at least 7 lines, some
// of them saying literally "NOT a trainer_links relationship check". Scanning
// the raw text would be born with 7 false positives and would be worthless.
//
// The stripper is string-aware rather than a blind `//` cut: match paths carry
// single slashes (`/databases/$(database)/documents/...`) and never a double
// one, and single-quoted literals could in principle hold a `//`. The test
// "the comment stripper does not damage code" below verifies empirically that
// no `match` / `function` / `allow` line was harmed.

function stripComments(source: string): string {
  let out = "";
  let inString = false;
  let i = 0;
  while (i < source.length) {
    const c = source[i];
    if (inString) {
      out += c;
      if (c === "\\") {
        out += source[i + 1] ?? "";
        i += 2;
        continue;
      }
      if (c === "'") inString = false;
      i += 1;
      continue;
    }
    if (c === "'") {
      inString = true;
      out += c;
      i += 1;
      continue;
    }
    if (c === "/" && source[i + 1] === "/") {
      // Drop up to (not including) the newline so line numbers stay aligned
      // with the real file — every diagnostic below quotes a usable line.
      while (i < source.length && source[i] !== "\n") i += 1;
      continue;
    }
    out += c;
    i += 1;
  }
  if (inString) {
    throw new Error("firestore.rules: unterminated string literal while stripping comments");
  }
  return out;
}

// ---------------------------------------------------------------------------
// 2. Structural parser — strict by design.
// ---------------------------------------------------------------------------

function parseRules(stripped: string): { functions: Map<string, RuleFunction>; clauses: AllowClause[] } {
  const functions = new Map<string, RuleFunction>();
  const clauses: AllowClause[] = [];
  const pathStack: string[] = [];
  let pos = 0;

  const lineAt = (at: number): number => stripped.slice(0, at).split("\n").length;

  const fail = (message: string): never => {
    const snippet = stripped.slice(pos, pos + 80).replace(/\s+/g, " ").trim();
    throw new Error(`firestore.rules:${lineAt(pos)} — ${message}. Next: "${snippet}"`);
  };

  const skipWs = (): void => {
    while (pos < stripped.length && /\s/.test(stripped[pos])) pos += 1;
  };

  const tryConsume = (re: RegExp): RegExpMatchArray | null => {
    const m = stripped.slice(pos).match(re);
    if (m === null) return null;
    pos += m[0].length;
    return m;
  };

  /** Reads to the `}` closing a block whose `{` was already consumed. */
  const readBalancedBody = (): string => {
    const start = pos;
    let depth = 1;
    let inString = false;
    while (pos < stripped.length) {
      const c = stripped[pos];
      if (inString) {
        if (c === "\\") pos += 1;
        else if (c === "'") inString = false;
      } else if (c === "'") {
        inString = true;
      } else if (c === "{") {
        depth += 1;
      } else if (c === "}") {
        depth -= 1;
        if (depth === 0) {
          const body = stripped.slice(start, pos);
          pos += 1;
          return body;
        }
      }
      pos += 1;
    }
    return fail("unbalanced braces — block never closes");
  };

  /** Reads an `allow` expression to its terminating `;` (expressions are multiline). */
  const readToSemicolon = (): string => {
    const start = pos;
    let inString = false;
    while (pos < stripped.length) {
      const c = stripped[pos];
      if (inString) {
        if (c === "\\") pos += 1;
        else if (c === "'") inString = false;
      } else if (c === "'") {
        inString = true;
      } else if (c === ";") {
        const expr = stripped.slice(start, pos);
        pos += 1;
        return expr;
      }
      pos += 1;
    }
    return fail("allow clause never terminates with ';'");
  };

  const parseBlockBody = (): void => {
    for (;;) {
      skipWs();
      if (pos >= stripped.length) fail("unexpected end of file — a block was left open");

      if (stripped[pos] === "}") {
        pos += 1;
        return;
      }

      // `\S+` must stay GREEDY: a lazy quantifier stops at the first `{`,
      // which in `/users/{uid}` is the wildcard, not the block opener.
      const matchStmt = tryConsume(/^match\s+(\S+)\s*\{/);
      if (matchStmt !== null) {
        pathStack.push(matchStmt[1]);
        parseBlockBody();
        pathStack.pop();
        continue;
      }

      const fnStmt = tryConsume(/^function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\([^)]*\)\s*\{/);
      if (fnStmt !== null) {
        const line = lineAt(pos);
        const name = fnStmt[1];
        if (functions.has(name)) {
          // A duplicated name would make the flat call graph below wrong
          // (scope would start to matter). Fail loud rather than guess.
          throw new Error(`firestore.rules:${line} — duplicate helper name "${name}"; the scanner assumes unique names`);
        }
        functions.set(name, { name, body: readBalancedBody(), line });
        continue;
      }

      const allowStmt = tryConsume(/^allow\s+([A-Za-z,\s]+?)\s*:\s*if\b/);
      if (allowStmt !== null) {
        const line = lineAt(pos);
        const verbs = allowStmt[1].split(",").map((v) => v.trim()).filter((v) => v.length > 0);
        for (const verb of verbs) {
          if (!(KNOWN_VERBS as readonly string[]).includes(verb)) {
            throw new Error(`firestore.rules:${line} — unknown allow verb "${verb}"; teach the scanner before shipping it`);
          }
        }
        const full = pathStack.join("");
        const scoped = full.startsWith(DOCUMENTS_ROOT) ? full.slice(DOCUMENTS_ROOT.length) : full;
        clauses.push({ path: scoped, verbs, expr: readToSemicolon(), line });
        continue;
      }

      fail("unrecognized construct (expected match / function / allow / '}')");
    }
  };

  skipWs();
  if (tryConsume(/^rules_version\s*=\s*'[^']*'\s*;/) === null) fail("missing rules_version header");
  skipWs();
  if (tryConsume(/^service\s+[A-Za-z0-9_.]+\s*\{/) === null) fail("missing service declaration");
  parseBlockBody();
  skipWs();
  if (pos !== stripped.length) fail("trailing content after the service block");

  return { functions, clauses };
}

// ---------------------------------------------------------------------------
// 3. Identity, call graph, token reachability.
// ---------------------------------------------------------------------------

/**
 * Clause identity is match path + verbs — NOT a line number, so ordinary edits
 * to firestore.rules do not churn the frozen inventory. `/routines/{routineId}`
 * legitimately carries several `allow update` clauses, so repeats get a
 * document-order ordinal appended.
 */
function buildClauseIds(clauses: readonly AllowClause[]): string[] {
  const base = clauses.map((c) => `${c.path} :: ${c.verbs.join(",")}`);
  const total = new Map<string, number>();
  for (const b of base) total.set(b, (total.get(b) ?? 0) + 1);
  const seen = new Map<string, number>();
  return base.map((b) => {
    if (total.get(b) === 1) return b;
    const n = (seen.get(b) ?? 0) + 1;
    seen.set(b, n);
    return `${b} #${n}`;
  });
}

function tokensIn(text: string): string[] {
  return PAYWALL_TOKENS.filter((token) =>
    new RegExp(`(?<![A-Za-z0-9_])${token}(?![A-Za-z0-9_])`).test(text));
}

/** Helper names invoked directly in `text`. `.get(` and `$(x)` are not calls here. */
function directCalls(text: string, functions: ReadonlyMap<string, RuleFunction>): string[] {
  const out: string[] = [];
  const re = /(?<![A-Za-z0-9_.$])([A-Za-z_][A-Za-z0-9_]*)\s*\(/g;
  let m: RegExpExecArray | null = re.exec(text);
  while (m !== null) {
    if (functions.has(m[1])) out.push(m[1]);
    m = re.exec(text);
  }
  return out;
}

/** Transitive closure of the helper call graph. The `seen` set also breaks cycles. */
function reachableHelpers(text: string, functions: ReadonlyMap<string, RuleFunction>): Set<string> {
  const seen = new Set<string>();
  const pending = directCalls(text, functions);
  while (pending.length > 0) {
    const name = pending.pop();
    if (name === undefined || seen.has(name)) continue;
    seen.add(name);
    const fn = functions.get(name);
    if (fn === undefined) throw new Error(`call graph: helper "${name}" vanished from the function table`);
    for (const next of directCalls(fn.body, functions)) pending.push(next);
  }
  return seen;
}

/**
 * All the TEXT a clause can reach: its own expression PLUS the body of every
 * helper in its transitive closure.
 *
 * Exists so that a scan for something that is NOT a paywall token — §7 scans
 * for `session_shares` — gets the same reach as `reachableTokens` below. The
 * file cannot honestly claim closure for one assert and settle for the clause's
 * own text in another: `reactionPostReadable()` (firestore.rules ~675-697) is
 * live proof that a lookup inside a shared helper is the idiom here, and a
 * plain-text filter would let exactly that shape slip through unnoticed.
 */
function reachableText(clause: AllowClause, functions: ReadonlyMap<string, RuleFunction>): string {
  const chunks = [clause.expr];
  for (const name of reachableHelpers(clause.expr, functions)) {
    const fn = functions.get(name);
    if (fn === undefined) throw new Error(`reachable text: helper "${name}" vanished from the function table`);
    chunks.push(fn.body);
  }
  return chunks.join("\n");
}

/** Tokens a clause can reach: its own expression PLUS every helper it pulls in. */
function reachableTokens(clause: AllowClause, functions: ReadonlyMap<string, RuleFunction>): string[] {
  const found = new Set<string>(tokensIn(clause.expr));
  for (const name of reachableHelpers(clause.expr, functions)) {
    const fn = functions.get(name);
    if (fn === undefined) throw new Error(`token walk: helper "${name}" vanished from the function table`);
    for (const token of tokensIn(fn.body)) found.add(token);
  }
  return [...found].sort();
}

function buildModel(): RulesModel {
  const stripped = stripComments(RAW_RULES);
  const { functions, clauses } = parseRules(stripped);
  return { stripped, functions, clauses, ids: buildClauseIds(clauses) };
}

const MODEL = buildModel();

/** Every clause whose transitive closure mentions a paywall token, id -> tokens. */
const PAYWALL_AWARE: ReadonlyMap<string, readonly string[]> = (() => {
  const out = new Map<string, readonly string[]>();
  MODEL.clauses.forEach((clause, index) => {
    const tokens = reachableTokens(clause, MODEL.functions);
    if (tokens.length > 0) out.set(MODEL.ids[index], tokens);
  });
  return out;
})();

// ---------------------------------------------------------------------------
// 4. Sanity — a broken parser returning nothing must NOT pass silently.
// ---------------------------------------------------------------------------
// Everything below leans on these. The counts are cross-checked against an
// INDEPENDENT method (line matching on the stripped text) instead of a magic
// number, so the check survives ordinary edits to firestore.rules while still
// catching a parser that skipped constructs.

describe("rules scanner sanity", () => {
  it("parses every allow clause the stripped file contains", () => {
    const byLine = MODEL.stripped.split("\n").filter((l) => /^\s*allow\s/.test(l)).length;
    expect(byLine).toBeGreaterThan(50);
    expect(MODEL.clauses.length).toBe(byLine);
  });

  it("parses every helper the stripped file defines", () => {
    const byLine = MODEL.stripped.split("\n").filter((l) => /^\s*function\s+[A-Za-z_]/.test(l)).length;
    expect(byLine).toBeGreaterThan(10);
    expect(MODEL.functions.size).toBe(byLine);
  });

  it("tracks nested match paths, not just top-level collections", () => {
    expect(MODEL.clauses.map((c) => c.path)).toEqual(
      expect.arrayContaining([
        "/trainer_links/{linkId}",
        "/routines/{routineId}",
        "/posts/{postId}/reactions/{reactorUid}",
        "/chats/{chatId}/messages/{messageId}",
        "/users/{uid}/sessions/{sessionId}/setLogs/{setLogId}",
      ]),
    );
  });

  it("handles multiline expressions and multi-verb clauses", () => {
    const trainerLinkUpdate = MODEL.clauses.find(
      (c) => c.path === "/trainer_links/{linkId}" && c.verbs.join(",") === "update");
    expect(trainerLinkUpdate).toBeDefined();
    expect(trainerLinkUpdate?.expr.includes("\n")).toBe(true);

    const multiVerb = MODEL.clauses.filter((c) => c.verbs.length > 1);
    expect(multiVerb.length).toBeGreaterThan(0);
    expect(MODEL.clauses.some((c) => c.verbs.includes("read") && c.verbs.includes("write"))).toBe(true);
  });

  it("gives every clause a stable, unique identity", () => {
    expect(new Set(MODEL.ids).size).toBe(MODEL.ids.length);
    expect(MODEL.ids.every((id) => !/:\d+/.test(id))).toBe(true);
  });

  it("does not damage code while stripping comments", () => {
    const rawLines = RAW_RULES.split("\n");
    const strippedLines = MODEL.stripped.split("\n");
    expect(strippedLines.length).toBe(rawLines.length);

    rawLines.forEach((raw, i) => {
      if (!/^\s*(match|function|allow)\s/.test(raw)) return;
      expect(strippedLines[i].trim().length).toBeGreaterThan(0);
    });
    expect(MODEL.stripped).toContain("match /databases/{database}/documents {");
  });

  it("actually removes the prose mentions that would be false positives", () => {
    // firestore.rules explains in comments that several rules are role checks
    // and "NOT a trainer_links relationship check". Unstripped, each of those
    // sentences would land in the inventory as a phantom clause.
    expect(RAW_RULES).toContain("NOT a trainer_links relationship check");
    expect(MODEL.stripped).not.toContain("NOT a trainer_links relationship check");

    const count = (text: string): number => (text.match(/trainer_links/g) ?? []).length;
    expect(count(MODEL.stripped)).toBeLessThan(count(RAW_RULES));
    expect(count(MODEL.stripped)).toBeGreaterThan(0);
  });

  it("resolves paywall tokens THROUGH the helper call graph, not only inline", () => {
    // Positive control for the transitive closure. `/chats/{chatId}` create
    // has no paywall token in its own expression — it reaches trainer_links
    // only via chatCreateOk(). If this stops holding, the closure has gone
    // dead and the whole scanner is decorative.
    const chatsCreate = MODEL.clauses.find(
      (c) => c.path === "/chats/{chatId}" && c.verbs.join(",") === "create");
    expect(chatsCreate).toBeDefined();
    expect(tokensIn(chatsCreate?.expr ?? "")).toEqual([]);
    expect(reachableHelpers(chatsCreate?.expr ?? "", MODEL.functions)).toContain("chatCreateOk");
    expect(PAYWALL_AWARE.has("/chats/{chatId} :: create")).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// 5. ASSERT 1 — the frozen inventory.
// ---------------------------------------------------------------------------
// Exactly which clauses are allowed to know that the paywall exists. Adding a
// clause that touches any paywall token turns this red ON PURPOSE: the fix is
// to add it here consciously, after checking assert 2 below still holds.

const FROZEN_PAYWALL_AWARE_CLAUSES: Readonly<Record<string, readonly string[]>> = {
  // The entitlement field-pin: entitlement/blockedAt/blockedReason are
  // CF-write-only (paywall Fase 7 PR1, design 5.2). `acceptedAt` joins them in
  // slice 5 — pinned equal-to-existing so no member can rewrite the ordering
  // key that decides who keeps the slot.
  "/trainer_links/{linkId} :: update": [
    "acceptedAt", "blockedAt", "blockedReason", "entitlement",
  ],
  // The other half of the acceptedAt write path. The client DOES send this
  // field on create (TrainerLinkRepository.request() does set(toJson())), so
  // the create clause admits it only as null. A pin on one verb, documented as
  // if it covered both, is worse than no pin.
  "/trainer_links/{linkId} :: create": ["acceptedAt"],
  // Same shape for the trainer's own doc: create refuses `blockedAthleteIds`
  // outright, because the update pin below would make a value planted at
  // create INDELIBLE from the client.
  "/users/{uid} :: create": ["blockedAthleteIds"],
  // ADDED deliberately (paywall slice 5), not to make this test pass. The
  // `blockedAthleteIds` field-pin: the trainer's own doc now pins the
  // denormalized blocked-athlete list equal-to-existing, so only the Admin SDK
  // (reconcileEntitlements) can move it.
  //
  // The verb is what makes this admissible, and it is the only thing worth
  // checking here — for this entry and for the three slice-5 entries above:
  // every one of them is a `create` or `update` clause. They restrict WHO MAY
  // WRITE the field; none of them reads the field to authorize anything, and
  // no read verb shares an expression or a helper with them. §6 stays green
  // ON ITS OWN — it
  // is not suppressed and it was not touched. If a future edit lands
  // `blockedAthleteIds` in a read/get/list clause, §6 goes red and the answer
  // is to move the check to the write path, never to widen this table.
  "/users/{uid} :: update": ["blockedAthleteIds"],
  // chatCreateOk() reads the named link to prove a coach relationship before
  // a chat may be opened. Reaches trainer_links through the helper.
  "/chats/{chatId} :: create": ["trainer_links"],
  // A review may only be written against a real, non-terminated link
  // (rules-hardening Slice B, AD-1).
  "/reviews/{reviewId} :: create": ["trainer_links"],
};

describe("firestore.rules — frozen inventory of paywall-aware clauses", () => {
  it("no clause outside the inventory knows about the paywall", () => {
    expect(Object.fromEntries([...PAYWALL_AWARE].sort(([a], [b]) => a.localeCompare(b))))
      .toEqual(Object.fromEntries(
        Object.entries(FROZEN_PAYWALL_AWARE_CLAUSES).sort(([a], [b]) => a.localeCompare(b))));
  });

  it("every inventory entry still exists as a real clause", () => {
    for (const id of Object.keys(FROZEN_PAYWALL_AWARE_CLAUSES)) {
      expect(MODEL.ids).toContain(id);
    }
  });
});

// ---------------------------------------------------------------------------
// 6. ASSERT 2 — the invariant. This is the one that carries the weight.
// ---------------------------------------------------------------------------
// Read it as a sentence: NO RULE THAT DECIDES WHETHER SOMEONE CAN READ A
// DOCUMENT MAY DEPEND ON PAYWALL BLOCK STATE.
//
// The paywall restricts what a TRAINER can WRITE about a blocked athlete. The
// athlete keeps everything: their routine, their sessions, their set logs,
// their measurements, the chat with their coach, their billing history. That
// is a product decision, not an implementation detail — an athlete who paid
// nothing and did nothing wrong must never be punished for their trainer's
// unpaid subscription.
//
// SCOPE — say it exactly, because the value of this assert is that its green
// means one precise thing. It proves that no read clause NAMES a paywall
// token, and it proves it through the TRANSITIVE closure, so it catches the
// realistic version of the mistake: a helper shared between a read clause and
// a write clause (the `reactionPostReadable()` shape, firestore.rules
// ~675-697), where nothing at the read clause itself would look wrong.
//
// It does NOT prove that the athlete is safe. It cannot see the vector by
// DATA — a read clause that consults a document the paywall pipeline writes,
// without naming the paywall anywhere. `session_shares` is exactly that (see
// the file header), and §7 below is where it gets covered. Read a green here
// as "nobody wired the block check into a read clause", nothing wider.
//
// It is SEPARATE from the inventory above so its failure message is
// unambiguous: if the inventory test fails, someone added a clause and must
// think; if THIS test fails, someone is about to take data away from an
// athlete, and the answer is always to move the check to the write path.

describe("firestore.rules — the athlete never loses read access", () => {
  it("no read/get/list clause depends on paywall block state", () => {
    const offenders = MODEL.clauses
      .map((clause, index) => ({ clause, id: MODEL.ids[index] }))
      .filter(({ clause }) => clause.verbs.some((v) => (READ_VERBS as readonly string[]).includes(v)))
      .filter(({ id }) => PAYWALL_AWARE.has(id))
      .map(({ id, clause }) =>
        `${id} (firestore.rules:${clause.line}) reaches [${(PAYWALL_AWARE.get(id) ?? []).join(", ")}]`);

    expect(offenders).toEqual([]);
  });

  it("checks a meaningful number of read clauses (the filter is not vacuous)", () => {
    const readClauses = MODEL.clauses.filter(
      (c) => c.verbs.some((v) => (READ_VERBS as readonly string[]).includes(v)));
    expect(readClauses.length).toBeGreaterThan(20);
  });
});

// ---------------------------------------------------------------------------
// 7. ASSERT 3 — the owner branch short-circuits before session_shares.
// ---------------------------------------------------------------------------
// The three read clauses that touch paywall-written data WITHOUT naming the
// paywall. `session_shares/{athleteId}` is maintained by
// syncSessionShareOnTrainerLink, which fires on `trainer_links` writes — the
// same collection the entitlement sweep writes. §6 is blind to this by
// construction: there is no paywall token anywhere in these clauses.
//
// They are correct today, and the reason is ORDER: the owner branch is first,
// so `||` short-circuits and the athlete's own read never evaluates the get().
// firestore.rules:1721-1722 states it in prose ("Ordering is load-bearing:
// branches 1/2 short-circuit before any get()"), and prose does not fail a
// build.
//
// WHY THE REORDER IS WORTH ITS OWN ASSERT. Flipped, the athlete's own read
// begins by dereferencing a document the paywall pipeline DELETES when the
// link stops being live. It would still return the data — but only because
// the branch happens to be written `exists(...) && get(...)`. Drop that
// `exists()`, the ordinary "simplify the chain" edit, and get() on a missing
// document fails the whole rule EVALUATION: the OWNER comes back
// PERMISSION_DENIED on their own sessions. That is not hypothetical —
// firestore.rules:134-143 documents the same failure mode on `routines`, where
// it already shipped once and blanked the muscle-distribution charts.
// Owner-first makes the hazard unreachable; owner-second leaves it one
// careless edit away.
//
// HOW IT IS CHECKED — and why not with text. The obvious check is "there is a
// `||` somewhere between the owner match and the session_shares match", and it
// is WRONG: `(owner || X) && session_shares(...)` contains a `||` in exactly
// that slice while the lookup gates the ENTIRE expression, so the athlete's
// read of their own sessions starts depending on the paywall-written doc —
// the precise catastrophe this section exists to forbid. Text cannot see
// parentheses or precedence, so the check parses the expression into its
// boolean structure (§7.1) and asserts the property directly:
//
//   pin the owner predicate TRUE, then over EVERY truth assignment of the
//   remaining operands, short-circuit evaluation never evaluates an operand
//   that names session_shares.
//
// That single statement covers both halves of the old prose: branch ORDER
// (owner second → the lookup runs first → red) and ALTERNATIVE-ness (owner
// ANDed with the lookup, at any nesting depth → red).
//
// ROBUSTNESS: all whitespace is squeezed out before parsing, so line
// re-wrapping, re-indentation and formatter runs cannot move these. What DOES
// (deliberately) break it is a semantic edit: reordering the branches, ANDing
// the owner check with the lookup, or moving the lookup into a helper.

/** Whitespace carries no meaning in a rules expression — drop it entirely. */
function squeeze(text: string): string {
  return text.replace(/\s+/g, "");
}

/** Lowest index at which any of `needles` occurs, or -1 if none of them does. */
function firstIndexOfAny(haystack: string, needles: readonly string[]): number {
  const hits = needles.map((n) => haystack.indexOf(n)).filter((i) => i >= 0);
  return hits.length === 0 ? -1 : Math.min(...hits);
}

// ---------------------------------------------------------------------------
// 7.1 Boolean structure of a rules expression.
// ---------------------------------------------------------------------------
// Grammar, same precedence as the CEL-ish expression language firestore.rules
// uses (`&&` binds tighter than `||`):
//
//   or   := and ( '||' and )*
//   and  := prim ( '&&' prim )*
//   prim := '(' or ')' | atom
//
// Parens are OVERLOADED in this file: `exists(...)`, `get(...)` and
// `$(database)` are CALLS, not grouping. A '(' opens a group only when the
// character before it cannot end an identifier; anything else is swallowed
// whole into the atom. That is deliberately conservative — a `||` hidden
// inside something the parser took for a call would stay hidden — and the
// round-trip check in `analyzeShortCircuit` is what keeps the conservatism
// honest: serialising the tree must reproduce the input character for
// character, so a construct the parser mangled fails loudly instead of
// quietly weakening the assert.
//
// NOT SUPPORTED ON PURPOSE: unary `!`. None of the three clauses uses it, and
// negation flips which branch short-circuits, so guessing would be worse than
// failing. `parseBoolExpr` throws when it sees one — teach it before shipping
// a rule that needs it.

type BoolNode =
  | { readonly kind: "atom"; readonly text: string }
  | { readonly kind: "group"; readonly inner: BoolNode }
  | { readonly kind: "and"; readonly parts: readonly BoolNode[] }
  | { readonly kind: "or"; readonly parts: readonly BoolNode[] };

/** Parses WHITESPACE-FREE text (run `squeeze` first). */
function parseBoolExpr(squeezed: string): BoolNode {
  let pos = 0;

  const fail = (message: string): never => {
    throw new Error(`boolean parse at ${pos}: ${message}. In: "${squeezed}"`);
  };

  // `]` is here for `members[0]`-style suffixes: the '(' of a call may follow
  // an index just as it may follow a name.
  const endsIdentifier = (c: string | undefined): boolean =>
    c !== undefined && /[A-Za-z0-9_$.\]]/.test(c);

  function parsePrimary(): BoolNode {
    if (squeezed[pos] === "(" && !endsIdentifier(squeezed[pos - 1])) {
      pos += 1;
      const inner = parseOr();
      if (squeezed[pos] !== ")") fail("group never closes");
      pos += 1;
      return { kind: "group", inner };
    }

    const start = pos;
    let depth = 0;
    while (pos < squeezed.length) {
      const c = squeezed[pos];
      // `!=` is a comparison and stays inside the atom; a bare `!` is negation.
      if (c === "!" && squeezed[pos + 1] !== "=") fail("unary '!' is not supported — teach the parser first");
      if (c === "(") {
        depth += 1;
      } else if (c === ")") {
        if (depth === 0) break;
        depth -= 1;
      } else if (depth === 0 && (squeezed.startsWith("&&", pos) || squeezed.startsWith("||", pos))) {
        break;
      }
      pos += 1;
    }
    if (pos === start) fail("empty operand");
    return { kind: "atom", text: squeezed.slice(start, pos) };
  }

  function parseAnd(): BoolNode {
    const parts = [parsePrimary()];
    while (squeezed.startsWith("&&", pos)) {
      pos += 2;
      parts.push(parsePrimary());
    }
    return parts.length === 1 ? parts[0] : { kind: "and", parts };
  }

  function parseOr(): BoolNode {
    const parts = [parseAnd()];
    while (squeezed.startsWith("||", pos)) {
      pos += 2;
      parts.push(parseAnd());
    }
    return parts.length === 1 ? parts[0] : { kind: "or", parts };
  }

  const root = parseOr();
  if (pos !== squeezed.length) fail("trailing content after the expression");
  return root;
}

/** Round-trip partner of the parser: must rebuild the input exactly. */
function serializeBool(node: BoolNode): string {
  switch (node.kind) {
    case "atom":
      return node.text;
    case "group":
      return `(${serializeBool(node.inner)})`;
    case "and":
      return node.parts.map(serializeBool).join("&&");
    case "or":
      return node.parts.map(serializeBool).join("||");
  }
}

function atomsOf(node: BoolNode): string[] {
  switch (node.kind) {
    case "atom":
      return [node.text];
    case "group":
      return atomsOf(node.inner);
    case "and":
    case "or":
      return node.parts.flatMap(atomsOf);
  }
}

/**
 * Short-circuit evaluation with the OWNER operand pinned true and every other
 * operand read from `assignment`. Records the first operand naming the lookup
 * that actually gets EVALUATED — reaching it is the failure, whatever it
 * returns.
 */
function evalShortCircuit(
  node: BoolNode,
  isOwner: (text: string) => boolean,
  isLookup: (text: string) => boolean,
  assignment: ReadonlyMap<string, boolean>,
  hit: { atom: string },
): boolean {
  switch (node.kind) {
    case "group":
      return evalShortCircuit(node.inner, isOwner, isLookup, assignment, hit);
    case "and":
      for (const part of node.parts) {
        if (!evalShortCircuit(part, isOwner, isLookup, assignment, hit)) return false;
      }
      return true;
    case "or":
      for (const part of node.parts) {
        if (evalShortCircuit(part, isOwner, isLookup, assignment, hit)) return true;
      }
      return false;
    case "atom": {
      if (isOwner(node.text)) return true;
      if (isLookup(node.text) && hit.atom === "") hit.atom = node.text;
      const value = assignment.get(node.text);
      if (value === undefined) throw new Error(`short-circuit eval: no assignment for operand "${node.text}"`);
      return value;
    }
  }
}

interface ShortCircuitAnalysis {
  /** Operands recognised as the data owner's predicate. Empty = the case is stale. */
  readonly ownerAtoms: readonly string[];
  /** Operands naming the lookup. Empty = it left the clause. */
  readonly lookupAtoms: readonly string[];
  /**
   * One readable witness per truth assignment under which the owner still
   * reaches the lookup. EMPTY IS THE PASSING VALUE.
   */
  readonly witnesses: readonly string[];
}

/** Beyond this the exhaustive enumeration stops being cheap; fail loud instead. */
const MAX_FREE_OPERANDS = 16;
const MAX_WITNESSES = 3;

function brief(text: string): string {
  return text.length <= 64 ? text : `${text.slice(0, 61)}...`;
}

/**
 * Proves — or refutes — "when the owner predicate holds, the lookup is never
 * evaluated", exhaustively over every truth assignment of the other operands.
 */
function analyzeShortCircuit(
  squeezedExpr: string,
  ownerForms: readonly string[],
  lookupNeedle: string,
): ShortCircuitAnalysis {
  const root = parseBoolExpr(squeezedExpr);
  const rebuilt = serializeBool(root);
  if (rebuilt !== squeezedExpr) {
    throw new Error(
      `boolean parser lost information — the analysis below would be unsound:\n  in:  ${squeezedExpr}\n  out: ${rebuilt}`);
  }

  const atoms = [...new Set(atomsOf(root))];
  const isOwner = (text: string): boolean => ownerForms.includes(text);
  const isLookup = (text: string): boolean => text.includes(lookupNeedle);

  // Owner operands are PINNED true, so only the rest get enumerated. Lookup
  // operands are enumerated like any other: whatever they return, evaluation
  // has to keep going past them to find any FURTHER reach.
  const free = atoms.filter((text) => !isOwner(text));
  if (free.length > MAX_FREE_OPERANDS) {
    throw new Error(
      `short-circuit analysis: ${free.length} free operands exceeds the ${MAX_FREE_OPERANDS} this ` +
      "exhaustive check enumerates — split the clause or raise the cap deliberately");
  }

  const witnesses: string[] = [];
  for (let mask = 0; mask < 2 ** free.length; mask += 1) {
    const assignment = new Map<string, boolean>(
      free.map((text, i) => [text, (mask & (1 << i)) !== 0]));
    const hit = { atom: "" };
    evalShortCircuit(root, isOwner, isLookup, assignment, hit);
    if (hit.atom !== "") {
      const given = free.map((text) => `${brief(text)}=${assignment.get(text) === true}`).join(", ");
      witnesses.push(`owner=true with [${given}] still evaluates ${brief(hit.atom)}`);
      if (witnesses.length >= MAX_WITNESSES) break;
    }
  }

  return { ownerAtoms: atoms.filter(isOwner), lookupAtoms: atoms.filter(isLookup), witnesses };
}

interface ShortCircuitCase {
  /** What the clause protects, used as the test name. */
  readonly what: string;
  readonly path: string;
  readonly verbs: string;
  /**
   * The predicate that lets the DATA OWNER through. Both orientations are
   * listed so `a == b` may be rewritten as `b == a` without a false red.
   */
  readonly ownerForms: readonly string[];
}

const SHORT_CIRCUIT_CASES: readonly ShortCircuitCase[] = [
  {
    what: "the athlete's own training sessions",
    path: "/users/{uid}/sessions/{sessionId}",
    verbs: "read",
    ownerForms: ["request.auth.uid==uid", "uid==request.auth.uid"],
  },
  {
    what: "the set logs inside those sessions",
    path: "/users/{uid}/sessions/{sessionId}/setLogs/{setLogId}",
    verbs: "read",
    ownerForms: ["request.auth.uid==uid", "uid==request.auth.uid"],
  },
  {
    what: "the athlete's own measurements",
    path: "/measurements/{measurementId}",
    verbs: "read",
    ownerForms: [
      "request.auth.uid==resource.data.athleteId",
      "resource.data.athleteId==request.auth.uid",
    ],
  },
];

describe("firestore.rules — the owner branch short-circuits before session_shares", () => {
  it.each(SHORT_CIRCUIT_CASES.map((c) => [c.what, c] as const))(
    "%s: the owner is matched before any session_shares lookup",
    (_what, testCase) => {
      const matches = MODEL.clauses.filter(
        (c) => c.path === testCase.path && c.verbs.join(",") === testCase.verbs);
      // Exactly one, or the identity below is ambiguous and the assert would
      // silently pin whichever clause happened to come first.
      expect(matches).toHaveLength(1);

      const expr = squeeze(matches[0].expr);

      // -1 here means the lookup left the clause — inlined elsewhere, moved
      // into a helper, or dropped. The analysis below only sees the clause's
      // own expression, so fail: re-derive the short-circuit argument by hand
      // and re-point this case. Do NOT delete the case. (A lookup that moved
      // into a HELPER also turns the cross-check at the bottom of this section
      // red, since that one walks the transitive closure.)
      const shares = expr.indexOf("session_shares");
      expect(shares).toBeGreaterThanOrEqual(0);

      const owner = firstIndexOfAny(expr, testCase.ownerForms);
      expect(owner).toBeGreaterThanOrEqual(0);
      // Cheap locator, kept only for the diagnostic it prints: it says WHERE
      // in the text the two live. It is strictly weaker than the structural
      // assert below and proves nothing on its own.
      expect(owner).toBeLessThan(shares);

      // THE assert. Not "there is a `||` between them" — `(owner || X) && shares`
      // satisfies that while the lookup gates the whole expression. This one
      // pins the owner predicate TRUE and enumerates every truth assignment of
      // the other operands: if ANY of them still reaches the lookup, the
      // athlete's own read depends on a paywall-written document.
      const analysis = analyzeShortCircuit(expr, testCase.ownerForms, "session_shares");
      // Both non-empty or the analysis is vacuous: no owner operand means the
      // ownerForms went stale, no lookup operand means there was nothing to
      // short-circuit past.
      expect(analysis.ownerAtoms.length).toBeGreaterThan(0);
      expect(analysis.lookupAtoms.length).toBeGreaterThan(0);
      expect(analysis.witnesses).toEqual([]);
    });

  it("still names three clauses — the set is not silently shrinking", () => {
    // Guards the it.each above against the failure mode where someone deletes
    // a case instead of re-deriving it.
    expect(SHORT_CIRCUIT_CASES).toHaveLength(3);

    // And cross-checks the other direction: no OTHER read clause started
    // consulting session_shares without being added here. The session_shares
    // rules block itself is exempt — its own match path is the collection.
    //
    // Through the TRANSITIVE CLOSURE, same as §5/§6, not the clause's own
    // text. Filtering on `c.expr` would miss the realistic shape: a clause
    // that reaches session_shares through a shared helper. That is not a
    // hypothetical here — `reactionPostReadable()` (firestore.rules ~691-697)
    // already serves read AND write from one helper, so lookups inside
    // helpers are the live idiom of this file, and such a clause would slip
    // past a plain-text filter in silence.
    const consumers = MODEL.clauses
      .filter((c) => c.verbs.some((v) => (READ_VERBS as readonly string[]).includes(v)))
      .filter((c) => !c.path.startsWith("/session_shares/"))
      .filter((c) => squeeze(reachableText(c, MODEL.functions)).includes("session_shares"))
      .map((c) => c.path);
    expect(consumers.sort()).toEqual(
      SHORT_CIRCUIT_CASES.map((c) => c.path).sort());
  });

  it("the cross-check really walks helpers (the closure is not decorative)", () => {
    // Non-vacuity control for the filter above: `reachableText` has to see
    // text that the clause's own expression does not contain. `/chats/{chatId}`
    // create is the standing example — `trainer_links` lives only inside
    // chatCreateOk(). If this goes red, the closure died and the cross-check
    // silently degraded to the plain-text scan it is meant to replace.
    const chatsCreate = MODEL.clauses.find(
      (c) => c.path === "/chats/{chatId}" && c.verbs.join(",") === "create");
    if (chatsCreate === undefined) throw new Error("/chats/{chatId} :: create vanished — re-point this control");
    expect(chatsCreate.expr).not.toContain("trainer_links");
    expect(reachableText(chatsCreate, MODEL.functions)).toContain("trainer_links");
  });
});

// ---------------------------------------------------------------------------
// 7.2 The analyzer under test — a check is only worth its own red.
// ---------------------------------------------------------------------------
// §7 leans entirely on `analyzeShortCircuit`, and an analyzer that returned
// "no witnesses" for everything would make all three cases green forever. So
// it is exercised against hand-written shapes, including the one the previous
// text check let through.

describe("the short-circuit analyzer", () => {
  const OWNER = ["request.auth.uid==uid"];
  const LOOKUP = "session_shares";
  const EXISTS = "exists(/databases/$(database)/documents/session_shares/$(uid))";
  const GET = "get(/databases/$(database)/documents/session_shares/$(uid)).data.trainerId==request.auth.uid";

  it.each([
    [
      "today's shape — owner first, inside an OR",
      `request.auth!=null&&(request.auth.uid==uid||(${EXISTS}&&${GET}))`,
      false,
    ],
    [
      "the owner branch ANDed with the lookup at the top level",
      `(request.auth.uid==uid||request.auth.uid==resource.data.coachId)&&${EXISTS}`,
      true,
    ],
    [
      "the branches flipped — lookup first",
      `request.auth!=null&&((${EXISTS}&&${GET})||request.auth.uid==uid)`,
      true,
    ],
    [
      "owner ANDed with the lookup directly",
      `request.auth!=null&&request.auth.uid==uid&&${EXISTS}`,
      true,
    ],
  ])("%s", (_what, expression, shouldReach) => {
    const analysis = analyzeShortCircuit(squeeze(expression), OWNER, LOOKUP);
    expect(analysis.ownerAtoms).toEqual(OWNER);
    expect(analysis.lookupAtoms.length).toBeGreaterThan(0);
    expect(analysis.witnesses.length > 0).toBe(shouldReach);
  });

  it("refuses to analyse what it cannot parse rather than passing it", () => {
    // Round-trip guard: a construct the parser mangles must throw, not come
    // back green with half the expression missing.
    expect(() => parseBoolExpr(squeeze("!isBlocked(uid) && request.auth.uid == uid")))
      .toThrow(/unary '!'/);
    expect(() => parseBoolExpr(squeeze("request.auth.uid == uid && (a || b")))
      .toThrow(/group never closes/);
    expect(() => parseBoolExpr(squeeze("request.auth.uid == uid && "))).toThrow(/empty operand/);
  });
});
