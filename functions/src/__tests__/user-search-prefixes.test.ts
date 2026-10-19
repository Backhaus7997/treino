/**
 * user-search-prefixes.test.ts — el escritor de
 * `userPublicProfiles.searchPrefixes` (#1478).
 *
 * LOCAL, sin emulador: Firestore es un doble que registra los `update()`.
 *
 * Tres capas:
 *   1. PARIDAD: el plegado contra `test/fixtures/search/user_search_terms.json`,
 *      los mismos vectores que leen la app (Dart) y el backfill (JS).
 *   2. DECISION: cuando hay que escribir y cuando no. El trigger se dispara
 *      con su propia escritura; si esta decision se equivoca, entra en loop.
 *   3. ESCRITURA: precondicion `lastUpdateTime`, y que un perfil que cambio o
 *      se borro despues del evento no se pise ni haga fallar la funcion.
 */

import { readFileSync } from "fs";
import { join } from "path";

jest.mock("firebase-functions/v2/firestore", () => ({
  onDocumentWritten: (_opts: unknown, handler: unknown) => handler,
}));

const mockUpdates: Array<{ path: string; data: unknown; precondition: unknown }> = [];
let mockFallaUpdateCon: number | undefined;

jest.mock("firebase-admin/firestore", () => ({
  getFirestore: () => ({
    doc: (path: string) => ({
      update: async (data: unknown, precondition: unknown) => {
        if (mockFallaUpdateCon !== undefined) {
          throw Object.assign(new Error("simulado"), { code: mockFallaUpdateCon });
        }
        mockUpdates.push({ path, data, precondition });
      },
    }),
  }),
}));

import type { App } from "firebase-admin/app";
import type { Timestamp } from "firebase-admin/firestore";
import {
  SEARCH_MAX_TOKENS,
  SEARCH_PREFIX_MAX,
  SEARCH_PREFIX_MIN,
  aplicarSearchPrefixes,
  searchPrefixesFor,
  searchPrefixesToWrite,
  searchTokens,
} from "../profile/user-search-prefixes";

interface Vectores {
  minPrefixLength: number;
  maxPrefixLength: number;
  maxTokens: number;
  cases: Array<{ input: string; tokens: string[]; prefixes: string[] }>;
}

const RAIZ = join(__dirname, "../../..");
const vectores: Vectores = JSON.parse(
  readFileSync(join(RAIZ, "test/fixtures/search/user_search_terms.json"), "utf8"),
);

const APP = {} as App;
const UPDATE_TIME = { seconds: 1 } as unknown as Timestamp;

function perfil(data: Record<string, unknown> | undefined) {
  return {
    exists: data !== undefined,
    data: () => data,
    updateTime: UPDATE_TIME,
  };
}

beforeEach(() => {
  mockUpdates.length = 0;
  mockFallaUpdateCon = undefined;
});

describe("paridad con los vectores compartidos", () => {
  it("usa los mismos topes que los vectores", () => {
    expect(SEARCH_PREFIX_MIN).toBe(vectores.minPrefixLength);
    expect(SEARCH_PREFIX_MAX).toBe(vectores.maxPrefixLength);
    expect(SEARCH_MAX_TOKENS).toBe(vectores.maxTokens);
  });

  it.each(vectores.cases.map((c) => [JSON.stringify(c.input), c] as const))(
    "%s",
    (_nombre, c) => {
      expect(searchTokens(c.input)).toEqual(c.tokens);
      expect(searchPrefixesFor(c.input)).toEqual(c.prefixes);
    },
  );

  it("un displayName que no es string no tiene prefijos", () => {
    expect(searchPrefixesFor(null)).toEqual([]);
    expect(searchPrefixesFor(undefined)).toEqual([]);
    expect(searchPrefixesFor(42)).toEqual([]);
  });
});

describe("searchPrefixesToWrite — cuando escribir", () => {
  it("doc borrado → nada", () => {
    expect(searchPrefixesToWrite(undefined)).toBeNull();
  });

  it("perfil sin el campo y con nombre → los prefijos (el backfill perezoso)", () => {
    expect(searchPrefixesToWrite({ displayName: "Juan P." })).toEqual([
      "ju",
      "jua",
      "juan",
    ]);
  });

  it("perfil sin el campo y sin nombre buscable → nada (no escribe [] de gusto)", () => {
    expect(searchPrefixesToWrite({ displayName: null })).toBeNull();
    expect(searchPrefixesToWrite({ displayName: "🔥" })).toBeNull();
    expect(searchPrefixesToWrite({})).toBeNull();
  });

  it("ya tiene lo que debe → nada: su propia escritura no lo dispara en loop", () => {
    expect(
      searchPrefixesToWrite({
        displayName: "Juan P.",
        searchPrefixes: ["ju", "jua", "juan"],
      }),
    ).toBeNull();
  });

  it("cambió el nombre → recalcula", () => {
    expect(
      searchPrefixesToWrite({
        displayName: "Ana",
        searchPrefixes: ["ju", "jua", "juan"],
      }),
    ).toEqual(["an", "ana"]);
  });

  it("le sacaron el nombre → vacía los prefijos viejos", () => {
    expect(
      searchPrefixesToWrite({ displayName: "", searchPrefixes: ["ju", "jua", "juan"] }),
    ).toEqual([]);
  });

  it("el campo tiene basura → lo corrige", () => {
    expect(
      searchPrefixesToWrite({ displayName: "Ana", searchPrefixes: "ana" }),
    ).toEqual(["an", "ana"]);
  });
});

describe("aplicarSearchPrefixes — la escritura", () => {
  it("escribe con precondición lastUpdateTime, sólo el campo", async () => {
    const r = await aplicarSearchPrefixes(APP, "u1", perfil({ displayName: "Martín López" }));
    expect(r).toBe("escrito");
    expect(mockUpdates).toEqual([
      {
        path: "userPublicProfiles/u1",
        data: {
          searchPrefixes: [
            "ma", "mar", "mart", "marti", "martin",
            "lo", "lop", "lope", "lopez",
          ],
        },
        precondition: { lastUpdateTime: UPDATE_TIME },
      },
    ]);
  });

  it("sin cambios → no escribe", async () => {
    const r = await aplicarSearchPrefixes(
      APP,
      "u1",
      perfil({ displayName: "Ana", searchPrefixes: ["an", "ana"] }),
    );
    expect(r).toBe("sin-cambios");
    expect(mockUpdates).toEqual([]);
  });

  it("doc borrado o evento sin after → no escribe", async () => {
    expect(await aplicarSearchPrefixes(APP, "u1", perfil(undefined))).toBe("sin-cambios");
    expect(await aplicarSearchPrefixes(APP, "u1", undefined)).toBe("sin-cambios");
    expect(mockUpdates).toEqual([]);
  });

  it.each([
    ["FAILED_PRECONDITION (cambió después del evento)", 9],
    ["NOT_FOUND (se borró después del evento)", 5],
  ])("%s → no pisa y no falla", async (_n, code) => {
    mockFallaUpdateCon = code;
    const r = await aplicarSearchPrefixes(APP, "u1", perfil({ displayName: "Ana" }));
    expect(r).toBe("obsoleto");
  });

  it("cualquier otro error se propaga (la invocación falla y se ve)", async () => {
    mockFallaUpdateCon = 14; // UNAVAILABLE
    await expect(
      aplicarSearchPrefixes(APP, "u1", perfil({ displayName: "Ana" })),
    ).rejects.toThrow("simulado");
  });
});
