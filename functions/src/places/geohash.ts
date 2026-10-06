/**
 * geohash5 — port de lib/core/utils/geohash.dart (el mismo que usa
 * scripts/seed_gyms.js y el `places-search.ts` archivado). Tiene que quedar en
 * lock-step con la versión Dart: la app consulta por estas celdas.
 */

const GEOHASH_BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";

export function geohash5(lat: number, lon: number): string {
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
