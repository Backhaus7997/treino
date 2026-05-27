'use strict';

/**
 * seed_gyms.js
 *
 * Seeds 20 gyms reales (Córdoba + Buenos Aires) en `gyms/{gymId}` con
 * `source: 'seed'`. Idempotente — re-ejecutarlo simplemente reescribe.
 *
 * Para Fase 6 Etapa 0 (trainer-multi-location).
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

// ── 20 gyms reales: Córdoba (7) + Buenos Aires (13) ──────────────────────
//
// Lat/lng aproximadas de Google Maps. Si alguna está fuera de su zona
// real (porque hay sucursales con el mismo nombre), corregir.
const GYMS = [
  // CÓRDOBA CAPITAL
  { id: 'megatlon-nueva-cordoba', name: 'Megatlon Nueva Córdoba', address: 'Av. H. Yrigoyen 384, Nueva Córdoba', lat: -31.4189, lng: -64.1859 },
  { id: 'megatlon-cerro-rosas', name: 'Megatlon Cerro de las Rosas', address: 'Av. Rafael Núñez 4630, Cerro de las Rosas', lat: -31.3727, lng: -64.2123 },
  { id: 'smartfit-cba-centro', name: 'SmartFit Córdoba Centro', address: 'Av. Colón 195, Centro', lat: -31.4127, lng: -64.1850 },
  { id: 'smartfit-villa-allende', name: 'SmartFit Villa Allende', address: 'Av. del Carmen 100, Villa Allende', lat: -31.2917, lng: -64.2980 },
  { id: 'sieger-gym-cba', name: 'Sieger Gym', address: 'Bv. San Juan 1051, Centro', lat: -31.4154, lng: -64.1995 },
  { id: 'rx-training-cba', name: 'RX Training', address: 'Av. Vélez Sársfield 1395, Nueva Córdoba', lat: -31.4244, lng: -64.1928 },
  { id: 'sport-cordoba-cba', name: 'Sport Córdoba', address: 'Av. Colón 1500, Alberdi', lat: -31.4078, lng: -64.2025 },

  // CABA — BELGRANO / NÚÑEZ / RECOLETA
  { id: 'megatlon-belgrano', name: 'Megatlon Belgrano', address: 'Av. Cabildo 2330, Belgrano', lat: -34.5598, lng: -58.4615 },
  { id: 'megatlon-recoleta', name: 'Megatlon Recoleta', address: 'Av. Las Heras 2333, Recoleta', lat: -34.5860, lng: -58.4015 },
  { id: 'always-nunez', name: 'Always Núñez', address: 'Av. Cabildo 3650, Núñez', lat: -34.5476, lng: -58.4775 },
  { id: 'fit-club-recoleta', name: 'Fit Club Recoleta', address: 'Junín 1247, Recoleta', lat: -34.5921, lng: -58.3950 },

  // CABA — PALERMO / VILLA CRESPO
  { id: 'megatlon-palermo', name: 'Megatlon Palermo', address: 'Av. Santa Fe 5025, Palermo', lat: -34.5786, lng: -58.4243 },
  { id: 'shape-palermo', name: 'Shape Palermo', address: 'Honduras 5650, Palermo', lat: -34.5847, lng: -58.4321 },

  // CABA — MICROCENTRO / CABALLITO / ALMAGRO
  { id: 'megatlon-microcentro', name: 'Megatlon Microcentro', address: 'Av. Corrientes 535, Microcentro', lat: -34.6037, lng: -58.3784 },
  { id: 'smartfit-caballito', name: 'SmartFit Caballito', address: 'Av. Rivadavia 5050, Caballito', lat: -34.6189, lng: -58.4426 },
  { id: 'smartfit-almagro', name: 'SmartFit Almagro', address: 'Av. Corrientes 4115, Almagro', lat: -34.6035, lng: -58.4197 },

  // GBA NORTE
  { id: 'sportclub-pilar', name: 'Sportclub Pilar', address: 'Av. Champagnat 2235, Pilar', lat: -34.4587, lng: -58.9145 },
  { id: 'sportclub-olivos', name: 'Sportclub Olivos', address: 'Av. del Libertador 2890, Olivos', lat: -34.5135, lng: -58.4945 },

  // GBA SUR
  { id: 'always-quilmes', name: 'Always Quilmes', address: 'Av. Hipólito Yrigoyen 280, Quilmes', lat: -34.7220, lng: -58.2540 },
  { id: 'megatlon-avellaneda', name: 'Megatlon Avellaneda', address: 'Av. Mitre 470, Avellaneda', lat: -34.6610, lng: -58.3673 },
];

async function run() {
  console.log(`Seeding ${GYMS.length} gyms...`);
  let written = 0;
  const now = admin.firestore.FieldValue.serverTimestamp();

  for (const g of GYMS) {
    const geohash = geohash5(g.lat, g.lng);
    await db.collection('gyms').doc(g.id).set({
      name: g.name,
      address: g.address,
      lat: g.lat,
      lng: g.lng,
      geohash,
      source: 'seed',
      createdAt: now,
    }, { merge: true });
    console.log(`  ✓ ${g.id} (${g.name}, geohash5=${geohash})`);
    written++;
  }

  console.log(`\n${written}/${GYMS.length} gyms seeded.`);
  process.exit(0);
}

run().catch((err) => {
  console.error('FAILED:', err);
  process.exit(1);
});
