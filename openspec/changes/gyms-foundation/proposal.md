# Proposal: gyms-foundation

**Change**: `gyms-foundation`
**Branch**: `feat/gyms-foundation`
**Engram key**: `sdd/gyms-foundation/proposal`
**Depends on exploration**: engram `sdd/gyms-foundation/explore` (id 335)

## Why

Hoy conviven DOS sistemas de gimnasios en paralelo y desincronizados:

1. **Legacy hardcodeado** (athlete-facing, en producción): `_kHardcodedGyms` (3 entradas) en `profile_setup_providers.dart`, con un mapa duplicado de nombres `_kGymNames` + `gymNameFromId()` en `feed/domain/gym_name.dart` que hace fallback a `id.toUpperCase()` cuando el id no está en el catálogo (señal de "catálogo stale" visible en la UI). Modelo propio pobre `profile_setup/domain/gym.dart` (`{id,name,address}`, sin geo, sin freezed). Es lo que alimenta `UserProfile.gymId` y `UserPublicProfile.gymId`.
2. **Colección first-class `gyms/`** (trainer-only): modelo rico `gyms/domain/gym.dart` (freezed + geo requerido + `source`), `GymRepository` (read-only), providers async (`gymsProvider`, `gymByIdProvider`), seed en `scripts/seed_gyms.js`. NO está conectada al flujo del atleta.

Esta fragmentación causa: nombres inconsistentes (el atleta ve `SMART-FIT-PALERMO` en mayúsculas), imposibilidad de agregar datos de gimnasio (dirección, geo) al flujo del atleta, y — lo más importante — **bloquea la feature futura de "rankings por gimnasio"** (rachas, volumen histórico, levantamientos principales, todo scoped por gym). Un ranking necesita una referencia de gimnasio única, curada y confiable donde muchos usuarios apunten al MISMO doc canónico. Con dos sistemas y ids legacy sueltos, un ranking se fragmentaría.

**Este cambio es la FUNDACIÓN de ese ranking, no el ranking en sí.** El objetivo acotado: un catálogo de gimnasios curado, unificado y nationwide-capable, con Córdoba como foco inicial de curación, sobre `gyms/` como única fuente de verdad.

### Decisiones de producto LOCKED (acotan el scope)

- **Solo gimnasios curados — SIN alta self-service del atleta.** El equipo carga los gimnasios vía seed. El atleta BUSCA y SELECCIONA del catálogo curado; si su gimnasio no está, no puede agregarlo (lo agregamos nosotros después). Consecuencia directa: este cambio **NO toca `firestore.rules`**, **NO agrega `createSelfService()`**, y **NO relaja `lat`/`lng`/`geohash` a opcionales**. El atleta solo LEE + selecciona. Esto deliberadamente descarta la pieza de mayor riesgo que marcó la exploración (relajar el role gate de rules es un cambio security-sensitive; ya no aplica).
- **Córdoba primero, base nationwide-capable.** Seedear los gimnasios principales de Córdoba ahora, pero el modelo y el picker/search NO se limitan geográficamente a Córdoba: la arquitectura queda lista para escalar a todo el país.

## What Changes

### 1. Modelo unificado — `gyms/` como única fuente de verdad
- Adoptar `lib/features/gyms/domain/gym.dart` (`Gym` rico, freezed) como el ÚNICO modelo de gimnasio.
- Retirar el modelo legacy `lib/features/profile_setup/domain/gym.dart`.
- Retirar `_kHardcodedGyms` + `gymSearchQueryProvider` + `filteredGymsProvider` de `profile_setup/application/profile_setup_providers.dart`.
- Retirar el mapa duplicado `_kGymNames` de `lib/features/feed/domain/gym_name.dart`.
- **`lat`/`lng`/`geohash` quedan REQUERIDOS** — los gimnasios curados siempre tienen coordenadas. NO se relaja el schema (deriva de la decisión "solo curados").
- Preservar el sentinel `kNoGymId = 'no-gym'` (opción "sin gimnasio").

### 2. Picker de gimnasio del atleta — sync → async
- Migrar `step_2_gym.dart` (onboarding) y `profile_gym_screen.dart` (edición standalone) de `filteredGymsProvider` (sync) a `gymsProvider` (FutureProvider) con filtro/búsqueda client-side.
- Estados explícitos loading / error / retry, **espejando el patrón `_GymsSection` de `profile_edit_trainer_screen.dart`** (`gymsLoading`/`gymsErrored` con `ref.invalidate(gymsProvider)` en retry) — precedente real ya en el codebase.
- Búsqueda client-side (catálogo chico, ~20-100 docs): un provider derivado que observa `gymsProvider.valueOrNull` y filtra por nombre/dirección, reemplazando `filteredGymsProvider`.
- Preservar la opción "sin gimnasio" (`kNoGymId`).
- **Nunca requiere permiso de ubicación** para navegar/seleccionar (browse = full catalog fetch, sin geo query). Reusa la disciplina del "listAll fallback" ya documentada en `trainer_discovery_providers.dart`.

### 3. Resolución de nombres — reemplazar `gymNameFromId` con datos reales
- Reemplazar `gymNameFromId` en sus **7 call sites**: `feed_screen.dart`, `session_player_screen.dart`, `user_search_result_tile.dart`, `profile_cuenta_section.dart`, `friend_request_inbox_tile.dart`, `profile_avatar_card.dart`, `public_profile_hero.dart`.
- **Estrategia híbrida (evita N+1 y fetches innecesarios):**
  - **Contextos de lista/feed** (feed, inbox de solicitudes, resultados de búsqueda): **denormalizar `gymName` en `UserPublicProfile`** en el write-time (espeja el patrón ya existente `CheckIn.gymName`). Dual-write en el flujo de guardado de perfil.
  - **Contextos de detalle de un solo usuario** (pantallas de perfil, session player): usar `gymByIdProvider` (Riverpod cachea por id automáticamente), sin batch concern.
- **Backfill** de los `UserPublicProfile` existentes que no tengan el campo `gymName`.

### 4. Backfill de gymIds legacy
- Los docs de usuario existentes guardan ids legacy: `smart-fit-palermo`, `sportclub-belgrano`, `megatlon-recoleta`.
- Nota confirmada leyendo el seed: **`megatlon-recoleta` YA existe** en `gyms/` con ese mismo id exacto (sección CABA) → mapea 1:1 sin crear doc. Los otros dos (`smart-fit-palermo`, `sportclub-belgrano`) NO existen en el catálogo curado y requieren mapeo a un doc real de `gyms/`.
- Script `scripts/migrate_legacy_gym_ids.js` dev-first que mapea los ids legacy → docs reales de `gyms/`, **espejando la disciplina de `scripts/migrate_trainer_locations.js`**: idempotente (skip si ya migrado), dual-write coherente (`users` + `userPublicProfiles`, igual que el repo en runtime), conteo verificado en consola, `treino-dev` antes que `treino-prod`, verificar el conteo de atletas prod con ids legacy antes de correrlo en prod.

### 5. Catálogo de Córdoba
- Reescribir/expandir `scripts/seed_gyms.js`: el seed actual es **7/20 Córdoba** (13 son CABA/GBA). Curar los gimnasios principales de Córdoba Capital (los 7 actuales + más), manteniendo `source: 'seed'`.
- El seed NO se limita a Córdoba a nivel arquitectura — Córdoba es el foco de curación inicial, no un límite del modelo ni del picker.
- **Decisión de diseño a resolver en `sdd-design`**: evaluar si agregar campos `city`/`province` al modelo `Gym` para habilitar filtrado nationwide futuro (se difiere la resolución final a la fase de diseño; NO se decide acá).

## Impact

### Áreas afectadas

| Área | Impacto | Detalle |
|------|---------|---------|
| `lib/features/gyms/domain/gym.dart` | Sin cambio de schema | Se adopta como fuente única; geo sigue requerido. Posible `city`/`province` según design. |
| `lib/features/profile_setup/domain/gym.dart` | **Borrado** | Modelo legacy retirado |
| `lib/features/profile_setup/application/profile_setup_providers.dart` | Modificado | Borrar `_kHardcodedGyms`, `gymSearchQueryProvider`, `filteredGymsProvider` |
| `lib/features/feed/domain/gym_name.dart` | **Borrado / vaciado** | Borrar `_kGymNames` + `gymNameFromId` |
| `lib/features/profile_setup/presentation/step_2_gym.dart` | Modificado | sync → async picker + search + loading/error/retry |
| `lib/features/profile/presentation/profile_gym_screen.dart` | Modificado | Igual migración (comparten `GymCard` por ADR-PSR-011) |
| `GymCard` widget | Modificado (mínimo) | Recibe `Gym` rico o `gym.name`/`gym.address ?? ''` |
| 7 call sites de `gymNameFromId` | Modificado | Migrar a `gymName` denormalizado (listas) o `gymByIdProvider` (detalle) |
| `UserPublicProfile` (modelo + write path en `UserRepository`) | Modificado | Nuevo campo `gymName` denormalizado + dual-write |
| `scripts/seed_gyms.js` | Reescrito | Foco Córdoba, nationwide-capable |
| `scripts/migrate_legacy_gym_ids.js` | Nuevo | Backfill ids legacy → docs reales |
| Backfill `UserPublicProfile.gymName` | Nuevo (script) | Rellenar campo `gymName` en docs existentes |

### Migración de datos
- **Sin migración de schema en `gyms/`**: los docs seed ya tienen coords; geo sigue requerido.
- **Backfill 1 (gymIds legacy)**: `smart-fit-palermo` y `sportclub-belgrano` → doc real de `gyms/`; `megatlon-recoleta` mapea 1:1 (ya existe). Dev-first, conteo verificado.
- **Backfill 2 (`gymName` denormalizado)**: rellenar `UserPublicProfile.gymName` para docs existentes, resolviendo el nombre desde `gyms/` por el `gymId` (ya backfilleado) del usuario. Orden: backfill de ids ANTES que backfill de nombres.

### Riesgos

| Riesgo | Probabilidad | Mitigación |
|--------|--------------|------------|
| Consistencia dual-write de `gymName` (perfil actualiza gym pero `gymName` queda stale) | Media | Dual-write atómico en el mismo write path; `gymByIdProvider` como fuente de verdad en detalle |
| N+1 al resolver nombres en listas | Media | Denormalización `gymName` en listas elimina el N+1 (mismo patrón que `CheckIn.gymName`) |
| `megatlon-recoleta` colisión/ambigüedad de id | Baja | Confirmado: mismo id exacto en seed → mapeo 1:1, no crea doc nuevo |
| Backfill prod remapea gym del atleta silenciosamente | Baja-Media | Dev-first, conteo verificado, idempotente; escalar a prod solo tras validar conteo (open question) |
| Regen freezed / call-site breaks al retirar modelo legacy | Baja | Sin cambio de schema en el modelo rico; solo borrado + reruteo de call sites; `flutter analyze` como gate |
| PR size > 400 LOC (cambio multi-pieza) | Media | Fundación multi-PR: dividir en slices (modelo+picker / name-resolution+backfill / catálogo). `sdd-tasks` define el corte. |

### Open decisions (para design / tasks)
1. **`city`/`province` en el modelo `Gym`**: ¿se agregan ahora para habilitar filtrado nationwide futuro, o se difiere? (resolver en `sdd-design`).
2. **Mapeo destino de ids legacy sin doc**: `smart-fit-palermo` y `sportclub-belgrano` → ¿a qué doc real de `gyms/` se mapean, o se crean docs nuevos con id consistente? (resolver en `sdd-design`; requiere criterio de naming de ids).
3. **Backfill en prod**: ¿es aceptable remapear silenciosamente el gym de atletas actuales, o requiere aviso/re-confirmación? (open question de producto; el explore la dejó abierta).
4. **Alcance del catálogo Córdoba v1**: ¿cuántas entradas es "suficiente" (10/20/40)? ¿Se mantiene o se descarta el catálogo CABA/GBA existente? (open question de producto).

### Out of Scope (explícito)
- Alta self-service de gimnasios por el atleta.
- Cualquier cambio en `firestore.rules` para `create` en `gyms/`.
- Método `createSelfService()`.
- Campos geo opcionales (geo sigue requerido).
- APIs externas de gimnasios (Google Places / OSM) — solo seed curado.
- Limitar geográficamente la UI a Córdoba (hard geo-limiting).
- La feature de ranking en sí (es la motivación downstream, no este cambio).
