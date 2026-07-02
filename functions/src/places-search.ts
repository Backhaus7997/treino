/**
 * SHELVED: cannot deploy under org code-assurance.com (Domain Restricted
 * Sharing blocks public invoker). App uses client-side Place Details
 * (Plan B). Restore the index.ts export + redeploy if the org later allows
 * public functions.
 *
 * resolveGymPlace — Firebase Callable Cloud Function for TREINO.
 *
 * Resolves a Google Places `placeId` into a `gyms/{placeId}` Firestore
 * document. Read-through cache: if the doc already exists, it is returned
 * as-is without calling the Google Places API. On a cache miss, this
 * function calls Place Details (New), maps the response onto the `Gym`
 * doc shape, and upserts `gyms/{placeId}` via the Admin SDK — which
 * bypasses the trainer-only client-side create rule (no rules change
 * needed, see firestore.rules comment on `gyms/{gymId}`).
 *
 * Pattern: pure handler (runResolveGymPlace) + thin onCall wrapper
 * (resolveGymPlace). Mirrors add-alias.ts / getApp() lazy Admin init.
 *
 * Places API (New) — Place Details:
 *   GET https://places.googleapis.com/v1/places/{placeId}
 *   Headers: X-Goog-Api-Key, X-Goog-FieldMask
 *   Query:   sessionToken (optional, shared with the client Autocomplete
 *            session per gym-places-search spec)
 *   Response fields used: id, displayName.text, formattedAddress,
 *   location.latitude/longitude, types.
 *
 * The Places server API key (`PLACES_API_KEY`) is provisioned via Secret
 * Manager (`firebase functions:secrets:set PLACES_API_KEY`) — never
 * hardcoded, never logged, never included in error messages sent to the
 * client (see errors below).
 *
 * Design: sdd/gym-google-places/design (#348).
 * Spec:   sdd/gym-google-places/spec — gym-places-search (#347).
 */

import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v2/https";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { FieldValue } from "firebase-admin/firestore";

/**
 * Initialize the default Admin SDK app lazily so the module can be imported
 * without an app already existing (e.g. in test environments that set up
 * their own named apps before importing).
 * Copied from add-alias.ts / review-aggregate.ts (same pattern).
 */
function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    // No default app yet — initialize one.
    return admin.initializeApp();
  }
}

const PLACES_DETAILS_FIELD_MASK =
  "id,displayName,formattedAddress,location,types";

/** Google types that soft-confirm a Place is gym-like. Logged only — never blocks. */
const GYM_LIKE_TYPES = ["gym", "health"];

// ---------------------------------------------------------------------------
// geohash5 — port of lib/core/utils/geohash.dart (same port already used by
// scripts/seed_gyms.js). Kept in lock-step with the Dart implementation.
// ---------------------------------------------------------------------------
const GEOHASH_BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";

function geohash5(lat: number, lon: number): string {
  let latMin = -90.0;
  let latMax = 90.0;
  let lonMin = -180.0;
  let lonMax = 180.0;
  let hash = "";
  let even = true;
  let bit = 0;
  let ch = 0;
  while (hash.length < 5) {
    if (even) {
      const mid = (lonMin + lonMax) / 2;
      if (lon >= mid) {
        ch = (ch << 1) | 1;
        lonMin = mid;
      } else {
        ch = ch << 1;
        lonMax = mid;
      }
    } else {
      const mid = (latMin + latMax) / 2;
      if (lat >= mid) {
        ch = (ch << 1) | 1;
        latMin = mid;
      } else {
        ch = ch << 1;
        latMax = mid;
      }
    }
    even = !even;
    bit++;
    if (bit === 5) {
      hash += GEOHASH_BASE32[ch];
      bit = 0;
      ch = 0;
    }
  }
  return hash;
}

interface PlaceDetailsResponse {
  id?: string;
  displayName?: { text?: string };
  formattedAddress?: string;
  location?: { latitude?: number; longitude?: number };
  types?: string[];
}

export interface ResolveGymPlaceResult {
  gymId: string;
  name: string;
  address: string | null;
  source: "google-places";
}

/**
 * Fetch Place Details (New) for the given placeId. Never leaks the API key
 * in any thrown error — only safe, generic messages reach the caller.
 */
async function fetchPlaceDetails(
  placeId: string,
  sessionToken: string | undefined,
  apiKey: string,
): Promise<PlaceDetailsResponse> {
  const url = new URL(`https://places.googleapis.com/v1/places/${placeId}`);
  if (sessionToken) {
    url.searchParams.set("sessionToken", sessionToken);
  }

  let response: Response;
  try {
    response = await fetch(url.toString(), {
      method: "GET",
      headers: {
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask": PLACES_DETAILS_FIELD_MASK,
      },
    });
  } catch {
    throw new HttpsError(
      "internal",
      "Failed to reach the Places API. Please try again.",
    );
  }

  if (response.status === 429) {
    throw new HttpsError(
      "resource-exhausted",
      "Places API rate limit reached. Please try again shortly.",
    );
  }

  if (!response.ok) {
    throw new HttpsError(
      "internal",
      "Places API request failed. Please try again.",
    );
  }

  return (await response.json()) as PlaceDetailsResponse;
}

/**
 * Core resolveGymPlace logic, extracted for unit-testability.
 * The caller supplies the firebase-admin App so tests can pass a named
 * emulator-backed app without relying on the default app.
 *
 * Read-through cache: if `gyms/{placeId}` already exists, it is returned
 * without calling the Places API. Otherwise Place Details (New) is called,
 * the response is mapped onto the Gym doc shape, and the doc is upserted.
 *
 * @param app          - firebase-admin App (default or named emulator app in tests)
 * @param placeId      - Google Places place_id, used verbatim as the gymId
 * @param sessionToken - optional Autocomplete session token, forwarded to
 *                       Place Details per the gym-places-search spec
 */
export async function runResolveGymPlace(
  app: admin.app.App,
  placeId: string,
  sessionToken?: string,
): Promise<ResolveGymPlaceResult> {
  // ── Guard: placeId must be non-empty ─────────────────────────────────────
  // Validated here (not only in the callable wrapper) so runResolveGymPlace
  // is independently testable without going through the onCall harness.
  if (!placeId) {
    throw new HttpsError("invalid-argument", "placeId is required.");
  }

  const db = admin.firestore(app);
  const gymRef = db.collection("gyms").doc(placeId);

  // ── Read-through cache ────────────────────────────────────────────────────
  const existing = await gymRef.get();
  if (existing.exists) {
    const data = existing.data() as {
      name: string;
      address?: string | null;
      source: string;
    };
    return {
      gymId: placeId,
      name: data.name,
      address: data.address ?? null,
      source: "google-places",
    };
  }

  // ── Cache miss: resolve via Place Details (New) ───────────────────────────
  const apiKey = process.env.PLACES_API_KEY;
  if (!apiKey) {
    throw new HttpsError(
      "internal",
      "Places API is not configured. Please try again later.",
    );
  }

  const details = await fetchPlaceDetails(placeId, sessionToken, apiKey);

  const name = details.displayName?.text;
  const lat = details.location?.latitude;
  const lng = details.location?.longitude;
  if (!name || typeof lat !== "number" || typeof lng !== "number") {
    throw new HttpsError(
      "internal",
      "Places API returned an incomplete result. Please try again.",
    );
  }
  const address = details.formattedAddress ?? null;

  // ── Soft gym-type check — log only, never rejects (per spec) ─────────────
  const types = details.types ?? [];
  const looksLikeGym = types.some((t) => GYM_LIKE_TYPES.includes(t));
  if (!looksLikeGym) {
    logger.warn(
      `resolveGymPlace: placeId=${placeId} has no gym-like Google ` +
        `types (${types.join(", ")}). Allowing selection per soft-check policy.`,
    );
  }

  await gymRef.set({
    id: placeId,
    name,
    address,
    lat,
    lng,
    geohash: geohash5(lat, lng),
    source: "google-places",
    brandId: null,
    brandName: null,
    branchName: null,
    createdAt: FieldValue.serverTimestamp(),
  });

  return { gymId: placeId, name, address, source: "google-places" };
}

/**
 * The v2 callable exported as the Firebase Function.
 * Named export so firebase-functions-test can wrap it directly.
 * Deployed to southamerica-east1, holds PLACES_API_KEY via Secret Manager.
 *
 * Operator setup: `firebase functions:secrets:set PLACES_API_KEY`.
 */
export const resolveGymPlace = functions.onCall(
  { region: "southamerica-east1", secrets: ["PLACES_API_KEY"] },
  async (request): Promise<ResolveGymPlaceResult> => {
    // ── Guard: caller must be authenticated ─────────────────────────────────
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const { placeId, sessionToken } = request.data as {
      placeId?: string;
      sessionToken?: string;
    };

    // ── Guard: placeId must be non-empty ────────────────────────────────────
    if (!placeId) {
      throw new HttpsError("invalid-argument", "placeId is required.");
    }

    return runResolveGymPlace(getApp(), placeId, sessionToken);
  },
);
