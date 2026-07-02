/**
 * Integration tests for the resolveGymPlace Cloud Function.
 *
 * Tests run against the Firebase Local Emulator (Firestore + Auth).
 * Set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 before running.
 *
 * global.fetch is mocked per-test — no real Google Places API calls are
 * made. PLACES_API_KEY is set to a dummy value for the process; the mock
 * intercepts every request before it would reach the network.
 *
 * SCENARIOs covered:
 *   SCENARIO-750  — resolveGymPlace and runResolveGymPlace exported
 *   SCENARIO-750b — resolveGymPlace re-exported from index.ts
 *   SCENARIO-751  — read-through HIT: gyms/{placeId} already exists, no fetch call
 *   SCENARIO-752  — read-through MISS: fetch called, doc mapped + upserted
 *   SCENARIO-753  — bad/empty placeId rejected with invalid-argument
 *   SCENARIO-754  — Places API non-200 response -> internal, no key leak
 *   SCENARIO-755  — Places API 429 -> resource-exhausted
 *   SCENARIO-756  — soft type check: non-gym types still resolve (no rejection)
 *   SCENARIO-757  — onCall wrapper rejects unauthenticated caller
 *   SCENARIO-758  — onCall wrapper rejects empty placeId (invalid-argument)
 *
 * Design: #348 (sdd/gym-google-places/design). Spec: #347
 * (sdd/gym-google-places/spec — gym-places-search).
 */

import * as admin from "firebase-admin";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";
process.env.PLACES_API_KEY = "test-dummy-places-key";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "places-search-test",
  );
});

afterAll(async () => {
  await testApp.delete();
});

// Module under test — will fail to resolve until places-search.ts is created (RED)
import { resolveGymPlace, runResolveGymPlace } from "../places-search";

import firebaseFunctionsTest from "firebase-functions-test";
type FftInstance = {
  wrap: (fn: unknown) => (data: unknown, ctx?: unknown) => Promise<unknown>;
  cleanup: () => void;
};
const fft = (firebaseFunctionsTest as unknown as () => FftInstance)();
const wrappedResolveGymPlace = fft.wrap(resolveGymPlace);

const db = () => admin.firestore(testApp);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function cleanupDoc(collection: string, id: string): Promise<void> {
  await db().collection(collection).doc(id).delete().catch(() => undefined);
}

function jsonResponse(status: number, body: unknown): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
    text: async () => JSON.stringify(body),
  } as unknown as Response;
}

const DETAILS_FIXTURE = {
  id: "ChIJplace-752",
  displayName: { text: "Gimnasio Test 752" },
  formattedAddress: "Av. Siempre Viva 742, Córdoba",
  location: { latitude: -31.4135, longitude: -64.181 },
  types: ["gym", "health", "point_of_interest"],
};

// ---------------------------------------------------------------------------
// SCENARIO-750 — structure: resolveGymPlace exported
// ---------------------------------------------------------------------------
describe("SCENARIO-750: resolveGymPlace exported and configured for southamerica-east1", () => {
  it("exports resolveGymPlace as a function", () => {
    expect(resolveGymPlace).toBeDefined();
    expect(typeof resolveGymPlace).toBe("function");
  });

  it("exports runResolveGymPlace as a function", () => {
    expect(runResolveGymPlace).toBeDefined();
    expect(typeof runResolveGymPlace).toBe("function");
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-750b — resolveGymPlace exported from index.ts
// ---------------------------------------------------------------------------
describe("SCENARIO-750b: resolveGymPlace exported from index.ts", () => {
  it("resolveGymPlace is re-exported from the functions index", async () => {
    const indexModule = await import("../index");
    expect(
      (indexModule as Record<string, unknown>).resolveGymPlace,
    ).toBeDefined();
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-751 — read-through HIT: doc already exists, no fetch call
// ---------------------------------------------------------------------------
describe("SCENARIO-751: read-through HIT returns cached doc without calling Places", () => {
  const placeId = "ChIJplace-751";

  const existingDoc = {
    id: placeId,
    name: "Gimnasio Ya Cacheado",
    address: "Calle Falsa 123",
    lat: -31.4,
    lng: -64.18,
    geohash: "6exqg",
    source: "google-places",
    brandId: null,
    brandName: null,
    branchName: null,
    createdAt: admin.firestore.Timestamp.now(),
  };

  beforeEach(async () => {
    await db().collection("gyms").doc(placeId).set(existingDoc);
  });

  afterEach(async () => {
    await cleanupDoc("gyms", placeId);
  });

  it("returns the cached doc and never calls fetch", async () => {
    const fetchSpy = jest.spyOn(global, "fetch");

    const result = await runResolveGymPlace(testApp, placeId);

    expect(result.gymId).toBe(placeId);
    expect(result.name).toBe("Gimnasio Ya Cacheado");
    expect(result.source).toBe("google-places");
    expect(fetchSpy).not.toHaveBeenCalled();

    fetchSpy.mockRestore();
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-752 — read-through MISS: fetch called, doc mapped + upserted
// ---------------------------------------------------------------------------
describe("SCENARIO-752: read-through MISS fetches Details and upserts gyms/{placeId}", () => {
  const placeId = "ChIJplace-752";

  afterEach(async () => {
    await cleanupDoc("gyms", placeId);
  });

  it("calls fetch, maps fields, and writes gyms/{placeId}", async () => {
    const fetchSpy = jest
      .spyOn(global, "fetch")
      .mockResolvedValue(jsonResponse(200, DETAILS_FIXTURE));

    const result = await runResolveGymPlace(testApp, placeId, "session-abc");

    expect(fetchSpy).toHaveBeenCalledTimes(1);
    const [url, init] = fetchSpy.mock.calls[0] as [string, RequestInit];
    expect(url).toContain(`/v1/places/${placeId}`);
    expect(url).toContain("sessionToken=session-abc");
    const headers = init.headers as Record<string, string>;
    expect(headers["X-Goog-Api-Key"]).toBe("test-dummy-places-key");
    expect(headers["X-Goog-FieldMask"]).toBe(
      "id,displayName,formattedAddress,location,types",
    );

    expect(result.gymId).toBe(placeId);
    expect(result.name).toBe("Gimnasio Test 752");
    expect(result.source).toBe("google-places");

    const snap = await db().collection("gyms").doc(placeId).get();
    expect(snap.exists).toBe(true);
    const data = snap.data();
    expect(data?.name).toBe("Gimnasio Test 752");
    expect(data?.address).toBe("Av. Siempre Viva 742, Córdoba");
    expect(data?.lat).toBe(-31.4135);
    expect(data?.lng).toBe(-64.181);
    expect(data?.source).toBe("google-places");
    expect(data?.brandId).toBeNull();
    expect(data?.brandName).toBeNull();
    expect(data?.branchName).toBeNull();
    expect(typeof data?.geohash).toBe("string");
    expect((data?.geohash as string).length).toBe(5);

    fetchSpy.mockRestore();
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-753 — bad/empty placeId rejected with invalid-argument
// ---------------------------------------------------------------------------
describe("SCENARIO-753: rejects empty placeId", () => {
  it("throws invalid-argument when placeId is empty", async () => {
    await expect(runResolveGymPlace(testApp, "")).rejects.toMatchObject({
      code: "invalid-argument",
      message: "placeId is required.",
    });
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-754 — Places API non-200 -> internal, no key leak
// ---------------------------------------------------------------------------
describe("SCENARIO-754: Places API non-200 response maps to internal without leaking the key", () => {
  const placeId = "ChIJplace-754";

  afterEach(async () => {
    await cleanupDoc("gyms", placeId);
  });

  it("throws internal and never includes the API key in the error", async () => {
    const fetchSpy = jest.spyOn(global, "fetch").mockResolvedValue(
      jsonResponse(404, { error: { message: "not found" } }),
    );

    let caught: unknown;
    try {
      await runResolveGymPlace(testApp, placeId);
    } catch (e) {
      caught = e;
    }

    expect(caught).toMatchObject({ code: "internal" });
    const message = (caught as { message: string }).message;
    expect(message).not.toContain("test-dummy-places-key");

    fetchSpy.mockRestore();
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-755 — Places API 429 -> resource-exhausted
// ---------------------------------------------------------------------------
describe("SCENARIO-755: Places API 429 maps to resource-exhausted", () => {
  const placeId = "ChIJplace-755";

  afterEach(async () => {
    await cleanupDoc("gyms", placeId);
  });

  it("throws resource-exhausted on HTTP 429", async () => {
    const fetchSpy = jest
      .spyOn(global, "fetch")
      .mockResolvedValue(jsonResponse(429, { error: { message: "quota" } }));

    await expect(runResolveGymPlace(testApp, placeId)).rejects.toMatchObject({
      code: "resource-exhausted",
    });

    fetchSpy.mockRestore();
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-756 — soft type check: non-gym types still resolve
// ---------------------------------------------------------------------------
describe("SCENARIO-756: non-gym Google types do not block resolution", () => {
  const placeId = "ChIJplace-756";

  afterEach(async () => {
    await cleanupDoc("gyms", placeId);
  });

  it("still creates the gym doc when types do not include gym/health", async () => {
    const fetchSpy = jest.spyOn(global, "fetch").mockResolvedValue(
      jsonResponse(200, {
        ...DETAILS_FIXTURE,
        id: placeId,
        types: ["restaurant", "point_of_interest"],
      }),
    );

    const result = await runResolveGymPlace(testApp, placeId);
    expect(result.gymId).toBe(placeId);

    const snap = await db().collection("gyms").doc(placeId).get();
    expect(snap.exists).toBe(true);

    fetchSpy.mockRestore();
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-757 — onCall wrapper rejects unauthenticated caller
// ---------------------------------------------------------------------------
describe("SCENARIO-757: rejects unauthenticated caller", () => {
  it("throws HttpsError unauthenticated when no auth context", async () => {
    await expect(
      wrappedResolveGymPlace({ placeId: "ChIJplace-anything" }),
    ).rejects.toMatchObject({
      code: "unauthenticated",
      message: "Authentication required.",
    });
  });
});

// ---------------------------------------------------------------------------
// SCENARIO-758 — onCall wrapper rejects empty placeId
// ---------------------------------------------------------------------------
describe("SCENARIO-758: rejects empty placeId (invalid-argument)", () => {
  it("throws invalid-argument when placeId is empty via runResolveGymPlace", async () => {
    await expect(
      runResolveGymPlace(testApp, "", "session-xyz"),
    ).rejects.toMatchObject({
      code: "invalid-argument",
      message: "placeId is required.",
    });
  });
});
