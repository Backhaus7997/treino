'use strict';

/**
 * seed_gyms.js
 *
 * Seeds gyms reales (Córdoba + Buenos Aires) en `gyms/{gymId}` con
 * `source: 'seed'`. Idempotente — re-ejecutarlo simplemente reescribe.
 *
 * Two-level catalog (marca → sucursal, gyms-foundation Phase 1): cada doc
 * de `gyms/` es UNA sucursal y lleva `brandId` (slug estable de la cadena),
 * `brandName` y `branchName`. Un gym independiente (una sola sucursal) es
 * su propia marca: `brandId === id`, `branchName: null`, `name` = solo el
 * nombre de marca. Una cadena con N sucursales comparte `brandId` entre
 * todas y cada una tiene su propio `branchName`; `name` queda como
 * "{brandName} - {branchName}" (display compuesto, ya usado por
 * `gymNameFromId`/denormalización).
 *
 * USAGE
 *   $env:GOOGLE_APPLICATION_CREDENTIALS = "scripts\treino-dev-service-account.json"
 *   node scripts/seed_gyms.js
 */

const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

// ── geohash5 (port of lib/core/utils/geohash.dart) ───────────────────────
const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';
function geohash5(lat, lon) {
  let latMin = -90.0, latMax = 90.0;
  let lonMin = -180.0, lonMax = 180.0;
  let hash = '';
  let even = true;
  let bit = 0;
  let ch = 0;
  while (hash.length < 5) {
    if (even) {
      const mid = (lonMin + lonMax) / 2;
      if (lon >= mid) { ch = (ch << 1) | 1; lonMin = mid; }
      else { ch = ch << 1; lonMax = mid; }
    } else {
      const mid = (latMin + latMax) / 2;
      if (lat >= mid) { ch = (ch << 1) | 1; latMin = mid; }
      else { ch = ch << 1; latMax = mid; }
    }
    even = !even;
    bit++;
    if (bit === 5) {
      hash += BASE32[ch];
      bit = 0;
      ch = 0;
    }
  }
  return hash;
}

// ── Catálogo: brands → sucursales ─────────────────────────────────────────
//
// Lat/lng aproximadas de Google Maps. Si alguna está fuera de su zona
// real (porque hay sucursales con el mismo nombre), corregir.
//
// Cada entrada de `BRANDS` es una marca. `branches` con 2+ entradas =
// cadena multi-sucursal (comparten `brandId`). `branches` con 1 entrada =
// gym independiente (`brandId` === id de esa única sucursal).
const BRANDS = [
  // ── CÓRDOBA CAPITAL ──────────────────────────────────────────────────
  {
    brandId: 'megatlon',
    brandName: 'Megatlon',
    branches: [
      { id: 'megatlon-nueva-cordoba', branchName: 'Nueva Córdoba', address: 'Av. H. Yrigoyen 384, Nueva Córdoba', lat: -31.4189, lng: -64.1859, city: 'Córdoba', province: 'Córdoba' },
      { id: 'megatlon-cerro-rosas', branchName: 'Cerro de las Rosas', address: 'Av. Rafael Núñez 4630, Cerro de las Rosas', lat: -31.3727, lng: -64.2123, city: 'Córdoba', province: 'Córdoba' },
      // CABA — ya sembrados antes de esta migración, ahora bajo la misma marca.
      { id: 'megatlon-belgrano', branchName: 'Belgrano', address: 'Av. Cabildo 2330, Belgrano', lat: -34.5598, lng: -58.4615, city: 'CABA', province: 'Buenos Aires' },
      { id: 'megatlon-recoleta', branchName: 'Recoleta', address: 'Av. Las Heras 2333, Recoleta', lat: -34.5860, lng: -58.4015, city: 'CABA', province: 'Buenos Aires' },
      { id: 'megatlon-palermo', branchName: 'Palermo', address: 'Av. Santa Fe 5025, Palermo', lat: -34.5786, lng: -58.4243, city: 'CABA', province: 'Buenos Aires' },
      { id: 'megatlon-microcentro', branchName: 'Microcentro', address: 'Av. Corrientes 535, Microcentro', lat: -34.6037, lng: -58.3784, city: 'CABA', province: 'Buenos Aires' },
      { id: 'megatlon-avellaneda', branchName: 'Avellaneda', address: 'Av. Mitre 470, Avellaneda', lat: -34.6610, lng: -58.3673, city: 'Avellaneda', province: 'Buenos Aires' },
    ],
  },
  {
    brandId: 'smartfit',
    brandName: 'SmartFit',
    branches: [
      { id: 'smartfit-cba-centro', branchName: 'Córdoba Centro', address: 'Av. Colón 195, Centro', lat: -31.4127, lng: -64.1850, city: 'Córdoba', province: 'Córdoba' },
      { id: 'smartfit-villa-allende', branchName: 'Villa Allende', address: 'Av. del Carmen 100, Villa Allende', lat: -31.2917, lng: -64.2980, city: 'Villa Allende', province: 'Córdoba' },
      // CABA — ya sembrados antes de esta migración.
      { id: 'smartfit-caballito', branchName: 'Caballito', address: 'Av. Rivadavia 5050, Caballito', lat: -34.6189, lng: -58.4426, city: 'CABA', province: 'Buenos Aires' },
      { id: 'smartfit-almagro', branchName: 'Almagro', address: 'Av. Corrientes 4115, Almagro', lat: -34.6035, lng: -58.4197, city: 'CABA', province: 'Buenos Aires' },
      // Legacy hardcoded id (`gymNameFromId`/perfiles viejos) — ahora doc real.
      { id: 'smart-fit-palermo', branchName: 'Palermo', address: 'Av. Santa Fe 2543, Palermo', lat: -34.5851, lng: -58.4265, city: 'CABA', province: 'Buenos Aires' },
    ],
  },
  {
    brandId: 'sportclub',
    brandName: 'SportClub',
    branches: [
      { id: 'sportclub-pilar', branchName: 'Pilar', address: 'Av. Champagnat 2235, Pilar', lat: -34.4587, lng: -58.9145, city: 'Pilar', province: 'Buenos Aires' },
      { id: 'sportclub-olivos', branchName: 'Olivos', address: 'Av. del Libertador 2890, Olivos', lat: -34.5135, lng: -58.4945, city: 'Olivos', province: 'Buenos Aires' },
      // Legacy hardcoded id (`gymNameFromId`/perfiles viejos) — ahora doc real.
      { id: 'sportclub-belgrano', branchName: 'Belgrano', address: 'Cabildo 1789, Belgrano', lat: -34.5615, lng: -58.4589, city: 'CABA', province: 'Buenos Aires' },
    ],
  },
  {
    brandId: 'always',
    brandName: 'Always',
    branches: [
      { id: 'always-nunez', branchName: 'Núñez', address: 'Av. Cabildo 3650, Núñez', lat: -34.5476, lng: -58.4775, city: 'CABA', province: 'Buenos Aires' },
      { id: 'always-quilmes', branchName: 'Quilmes', address: 'Av. Hipólito Yrigoyen 280, Quilmes', lat: -34.7220, lng: -58.2540, city: 'Quilmes', province: 'Buenos Aires' },
    ],
  },

  // ── Independientes (una sola sucursal → brandId === id) ────────────────
  { brandId: 'sieger-gym-cba', brandName: 'Sieger Gym', branches: [{ id: 'sieger-gym-cba', branchName: null, address: 'Bv. San Juan 1051, Centro', lat: -31.4154, lng: -64.1995, city: 'Córdoba', province: 'Córdoba' }] },
  { brandId: 'rx-training-cba', brandName: 'RX Training', branches: [{ id: 'rx-training-cba', branchName: null, address: 'Av. Vélez Sársfield 1395, Nueva Córdoba', lat: -31.4244, lng: -64.1928, city: 'Córdoba', province: 'Córdoba' }] },
  { brandId: 'sport-cordoba-cba', brandName: 'Sport Córdoba', branches: [{ id: 'sport-cordoba-cba', branchName: null, address: 'Av. Colón 1500, Alberdi', lat: -31.4078, lng: -64.2025, city: 'Córdoba', province: 'Córdoba' }] },
  { brandId: 'fit-club-recoleta', brandName: 'Fit Club Recoleta', branches: [{ id: 'fit-club-recoleta', branchName: null, address: 'Junín 1247, Recoleta', lat: -34.5921, lng: -58.3950, city: 'CABA', province: 'Buenos Aires' }] },
  { brandId: 'shape-palermo', brandName: 'Shape Palermo', branches: [{ id: 'shape-palermo', branchName: null, address: 'Honduras 5650, Palermo', lat: -34.5847, lng: -58.4321, city: 'CABA', province: 'Buenos Aires' }] },
];

/** Nombre display: "{brand} - {branch}" para cadenas, solo brand si es independiente. */
function composeName(brandName, branchName) {
  return branchName ? `${brandName} - ${branchName}` : brandName;
}

function flattenDocs() {
  const docs = [];
  for (const brand of BRANDS) {
    const isChain = brand.branches.length > 1;
    for (const branch of brand.branches) {
      docs.push({
        id: branch.id,
        name: composeName(brand.brandName, isChain ? branch.branchName : null),
        address: branch.address,
        lat: branch.lat,
        lng: branch.lng,
        city: branch.city,
        province: branch.province,
        brandId: brand.brandId,
        brandName: brand.brandName,
        branchName: isChain ? branch.branchName : null,
      });
    }
  }
  return docs;
}

async function run() {
  const docs = flattenDocs();
  console.log(`Seeding ${docs.length} gyms (${BRANDS.length} brands)...`);
  let written = 0;
  const now = admin.firestore.FieldValue.serverTimestamp();

  for (const g of docs) {
    const geohash = geohash5(g.lat, g.lng);
    await db.collection('gyms').doc(g.id).set({
      name: g.name,
      address: g.address,
      lat: g.lat,
      lng: g.lng,
      geohash,
      city: g.city,
      province: g.province,
      brandId: g.brandId,
      brandName: g.brandName,
      branchName: g.branchName,
      source: 'seed',
      createdAt: now,
    }, { merge: true });
    console.log(`  ✓ ${g.id} (${g.name}, geohash5=${geohash})`);
    written++;
  }

  console.log(`\n${written}/${docs.length} gyms seeded.`);
  process.exit(0);
}

run().catch((err) => {
  console.error('FAILED:', err);
  process.exit(1);
});
