# Proposal: trainer-multi-location

**Change**: Fase 6 · Etapa 0 — Multi-location + virtual support para PFs
**Branch principal**: `feat/trainer-multi-location-foundations` (PR#1 de 5)
**Owner**: Dev B
**Date**: 2026-05-27
**Depends on**: Fase 5 Etapa 1 ✅ (UserProfile + TrainerPublicProfile schema), Fase 5 Etapa 2 ✅ (Discovery geohash query existente — será reemplazada)

---

## 1. Why

El modelo actual de Fase 5 Etapa 2 asume que **cada PF tiene una sola ubicación física** (`trainerLatitude / trainerLongitude / trainerGeohash` en singular en `UserProfile` y `trainerPublicProfiles`). Esto es incorrecto en la realidad del producto:

1. **Multi-gym**: un PF típicamente entrena en 2-3 gimnasios distintos. Hoy el atleta que vive cerca del gym A no encuentra al PF si el PF guardó la ubicación del gym B.
2. **PFs virtuales**: hay PFs que solo arman planes online + chat. El form actual los obliga a poner una ubicación física.
3. **Confusión semántica**: el botón "Detectar ubicación" actual guarda *dónde está parado el PF en ese momento*, no *dónde trabaja*. Cualquier movimiento del PF descalibra el discovery.

Descubierto durante el smoke de Fase 6 Etapa 1 (Trainer profile UI) — la branch `feat/trainer-profile-onboarding` quedó con WIP commit `1fba9f1` y NO se mergeó. El form va a reusarse al cerrar PR#3 de este rediseño.

---

## 2. What

### Modelo final

```dart
class UserProfile {
  // ... resto sin cambios ...

  // ── DEPRECATED (mantener por backward compat hasta cleanup PR) ──────────
  double? trainerLatitude;     // legacy, se elimina en PR de cleanup
  double? trainerLongitude;    // legacy
  String? trainerGeohash;      // legacy

  // ── NUEVO ───────────────────────────────────────────────────────────────
  /// Ubicaciones físicas donde trabaja. Puede estar vacío si solo es virtual.
  /// Mezcla gyms del catálogo (`gymId` no-null) + lugares propios (`customLabel`).
  @Default(<TrainerLocation>[]) List<TrainerLocation> trainerLocations;

  /// Array derivado en write-time desde `trainerLocations`. Necesario para
  /// el query `array-contains-any` de Discovery.
  @Default(<String>[]) List<String> trainerGeohashes;

  /// Flag explícito independiente. Combinaciones válidas:
  ///   - empty + true   → solo virtual
  ///   - non-empty + false → solo presencial
  ///   - non-empty + true  → híbrido (caso común)
  ///   - empty + false  → INVÁLIDO; UserRepository rechaza el update.
  @Default(false) bool trainerOffersOnline;
}

class TrainerLocation {
  String id;                  // uuid local, no Firestore doc id
  TrainerLocationType type;   // gym | custom
  String? gymId;              // referencia gyms/{gymId} si type == gym
  String? customLabel;        // 'Mi estudio en casa', etc. si type == custom
  double lat;
  double lng;
  String geohash;             // geohash5 calculado al guardar
}

enum TrainerLocationType { gym, custom }
```

### Nueva entidad: `gyms/{gymId}`

```dart
class Gym {
  String id;
  String name;          // 'Megatlon Belgrano', 'SmartFit Córdoba Centro'
  String? address;      // texto libre, opcional
  double lat;
  double lng;
  String geohash;
  GymSource source;     // seed | self-service
  String? createdBy;    // uid del PF que lo creó (solo si self-service)
  DateTime createdAt;
}

enum GymSource { seed, selfService }
```

Reglas Firestore para `gyms/{gymId}`:
- Read: cualquier user autenticado.
- Write create: PF autenticado con `role == 'trainer'`. Validación: `name`, `lat`, `lng`, `geohash`, `source: 'self-service'`, `createdBy: request.auth.uid` requeridos.
- Write update/delete: denegado del cliente. Solo admin (futura UI de moderación).

### Discovery query update

Antes:
```dart
where('trainerGeohash', isGreaterThanOrEqualTo: prefix5)
  .where('trainerGeohash', isLessThan: end)
```

Después:
```dart
where('trainerGeohashes', arrayContainsAny: neighborGeohashes)
```

Esto trae todos los PFs cuya `trainerGeohashes` contiene cualquier geohash5 del prefix del atleta. Resultados duplicados se deduplican client-side.

### Migration

Script `scripts/migrate_trainer_locations.js` (idempotente) que para cada doc de `trainerPublicProfiles/` con `trainerGeohash` no-null:
1. Construye `[{id: uuid, type: 'custom', customLabel: 'Ubicación principal', lat, lng, geohash}]`.
2. Setea `trainerLocations` (array), `trainerGeohashes: [geohash]`, `trainerOffersOnline: false` (default).
3. NO borra los campos legacy (eso queda para un cleanup PR cuando todas las clientes estén en la versión nueva).

### Seed inicial de gyms

Script `scripts/seed_gyms.js` con **~20 gyms reales** de Argentina (Córdoba + Buenos Aires). Lista a definir antes de mergear (probablemente Megatlon, SmartFit, Always, Sportclub + gyms locales conocidos).

---

## 3. Trade-offs lockeados (2026-05-27)

| # | Decisión | Rationale |
|---|---|---|
| 1 | **Híbrido gym + custom** (no solo gyms) | PFs que entrenan en su casa, parque o studio propio necesitan poder marcarlo. La diferencia visual entre gym y custom se mantiene en toda la UI (pines distintos, secciones separadas en el form, label distinto en el discovery). |
| 2 | **2 flags separados** (`trainerLocations` array + `trainerOffersOnline` bool) | Un PF puede trabajar presencial Y virtual a la vez (caso común). Un flag único `trainerIsVirtual` no captura esta combinación. La regla "empty + false = inválido" se valida en UserRepository (rechazo client-side antes del write). |
| 3 | **`gyms/` como collection first-class** (no embebido) | Cada gym tiene su propia ficha que puede crecer (foto, amenities, dirección). Si fuera embebido en cada PF, agregar un campo nuevo a Gym requeriría rewrite de todos los PFs que lo referencian. |
| 4 | **Self-service de gyms con `source: self-service`** | Si arrancamos solo con seed, los PFs no encuentran su gym y se frustran. Permitir agregar gym es UX-friendly. Validación post-hoc (admin elimina duplicados o spam). El `source` deja la puerta abierta para moderación + dedupe automático. |
| 5 | **`trainerLocations` embebido en `users/` y `trainerPublicProfiles/`** (no collection separada `trainer_locations/`) | Un PF tiene típicamente 1-5 ubicaciones, no 20+. Embebido evita N+1 queries y mantiene el dual-write atomic existente. Trade-off: limite implícito de ~10 ubicaciones por PF (suficiente para MVP). |
| 6 | **Mantener legacy `trainerLatitude/Longitude/Geohash` por 1 release** | Migration soft: la app nueva lee/escribe el array; clientes viejos siguen leyendo el campo legacy hasta que actualicen. Cleanup PR borra los campos legacy en Fase 6 más adelante. |

---

## 4. Partición en 5 PRs chained

| PR | Branch | Scope | LOC |
|---|---|---|---|
| **1** | `feat/trainer-multi-location-foundations` | Domain models (`TrainerLocation`, `Gym`) + repositories + dual-write extension + Firestore rules + seed + migration script. **Sin UI.** | ~700 |
| 2 | `feat/trainer-multi-location-discovery` | Discovery query update (`array-contains-any`) + `TrainerListTile` muestra ubicación más cercana + chip "Solo virtual" + dedup. | ~400 |
| 3 | `feat/trainer-multi-location-profile-edit` | Edit screen completo. Reusa el form de WIP commit `1fba9f1`. Secciones separadas (gyms / custom places / online switch). | ~700 |
| 4 | `feat/trainer-multi-location-map` | Map UI con múltiples pines por PF + cluster + íconos distintos gym/custom. | ~500 |
| 5 | `feat/trainer-multi-location-gym-self-service` | UI "Mi gym no está en la lista" → crea doc en `gyms/` con `source: self-service`. | ~300 |

**Total**: ~2600 LOC, ~5-7 días con un dev.

---

## 5. Out of scope (deferrables)

- Moderación de gyms self-service (admin UI para approve/reject) — futuro
- Importación masiva de gyms via Google Places API — futuro
- Schedule per location (horarios específicos por gym) — Fase 7 si producto lo pide
- "Buscar PFs que dan clases en MI gym" como filtro directo (hoy es por geohash genérico) — fácil follow-up
- Borrado de gyms self-service vacíos (sin PFs vinculados) — limpieza background

---

## 6. Risks

| # | Riesgo | Mitigación |
|---|---|---|
| 1 | Migration deja PFs con array vacío si `trainerGeohash` legacy está malformado | Script logea cada caso y skipea sin fallar. Output final lista los uid afectados para revisión manual. |
| 2 | Self-service genera gyms duplicados ("Megatlon Belgrano" + "megatlon Belgrano" + "Megatlon Bgo") | Dedupe client-side: al crear, fuzzy match contra los gyms existentes con geohash5 cercano. Si hay match >85% nombre, sugerir "¿Querés agregarte al gym X?". |
| 3 | Query `array-contains-any` tiene límite de 30 valores | El atleta consulta su geohash + ~8 vecinos = 9 valores. Bien dentro del límite. |
| 4 | Bundle size del seed inicial de gyms agrega ~5KB al app | Aceptable. El catalog se lee de Firestore en runtime, no se hardcodea en el binario. |

---

## 7. Success criteria

- [ ] Schema migration corrida en `treino-dev`; todos los PFs existentes (incluye Mateo) tienen `trainerLocations` no-vacío sin perder datos.
- [ ] Seed inicial de gyms corrido en `treino-dev`; ~20 docs en `gyms/`.
- [ ] Discovery query funciona end-to-end: atleta busca PF que tiene 2 ubicaciones, lo encuentra desde cualquiera de las 2.
- [ ] `UserRepository.update()` rechaza el caso `empty trainerLocations + offersOnline:false` con error claro.
- [ ] Firestore rules para `gyms/` deployadas + tests en `scripts/rules_test/`.
- [ ] `flutter analyze` 0 issues + suite full passing.
- [ ] Smoke end-to-end: PF agrega gym + custom location + activa online → atleta lo encuentra desde el gym; otro atleta lejos lo encuentra via filtro "Online".
