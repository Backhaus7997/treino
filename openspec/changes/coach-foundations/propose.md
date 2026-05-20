# Proposal: coach-foundations

**Change**: Fase 5 · Etapa 1 — Foundations del módulo Coach (modelos + reglas + Routine extension)
**Branch**: `feat/coach-foundations`
**Owner**: Dev B (reasignación 2026-05-20 — originalmente A en el roadmap)
**Date**: 2026-05-20
**Depends on**: nada (Fase 1 dio `UserProfile.role: athlete | trainer` que ya existe en main)

---

## 1. Why

Las 7 etapas restantes de Fase 5 (discovery, link lifecycle, chat, agenda, plans assignment mobile, Coach Hub web, Excel import) **todas** dependen de:
- Que el `UserProfile` del PF tenga campos profesionales (bio, especialidad, ubicación, tarifa).
- Que exista un modelo `TrainerLink` con repo y reglas Firestore para vincular PF ↔ atleta.
- Que el modelo `Routine` esté extendido para soportar planes privados asignados.

Sin esto, ninguna otra etapa puede arrancar. Esta es **la etapa bloqueante absoluta** de Fase 5.

---

## 2. What

### Production deliverables

**Extensión de modelos existentes**:
- `lib/features/profile/domain/user_profile.dart` — 5 campos nullable nuevos:
  - `trainerBio: String?` — descripción del PF
  - `trainerSpecialty: String?` — string libre por ahora (futuro: enum / list)
  - `trainerLocation: GeoPoint?` — lat/lng via `cloud_firestore.GeoPoint`
  - `trainerGeohash: String?` — precomputado client-side cuando se setea la location (Etapa 2 lo computa; Etapa 1 solo agrega el campo)
  - `trainerHourlyRate: int?` — pesos argentinos por hora (entero, sin centavos)
- `lib/features/workout/domain/routine.dart` — 4 campos nuevos:
  - `source: 'system' \| 'trainer-assigned' \| 'user-created'` — enum nuevo. Default `'system'` para retro-compat.
  - `assignedBy: String?` — trainerId
  - `assignedTo: String?` — athleteId
  - `visibility: 'public' \| 'private' \| 'shared'` — enum nuevo. Default `'public'`.

**Modelo nuevo**:
- `lib/features/coach/domain/trainer_link.dart`:
  ```dart
  @freezed
  class TrainerLink with _$TrainerLink {
    const factory TrainerLink({
      required String id,                  // doc id
      required String trainerId,
      required String athleteId,
      required TrainerLinkStatus status,   // pending|active|paused|terminated
      @TimestampConverter() required DateTime requestedAt,
      @TimestampConverter() DateTime? acceptedAt,
      @TimestampConverter() DateTime? terminatedAt,
      String? terminationReason,           // opcional
    }) = _TrainerLink;
    factory TrainerLink.fromJson(Map<String, Object?> json) =>
        _$TrainerLinkFromJson(json);
  }

  enum TrainerLinkStatus { pending, active, paused, terminated }
  ```
- Helper `TrainerLinkStatusX` extension con `fromJson/toJson` wire strings.

**Repo nuevo**:
- `lib/features/coach/data/trainer_link_repository.dart`:
  ```dart
  class TrainerLinkRepository {
    // PUBLIC API
    Future<TrainerLink> request({required String trainerId, required String athleteId});
    Future<void> accept(String linkId);
    Future<void> decline(String linkId);
    Future<void> terminate(String linkId, {String? reason});
    Future<List<TrainerLink>> listForTrainer(String trainerId, {Set<TrainerLinkStatus>? statuses});
    Future<List<TrainerLink>> listForAthlete(String athleteId, {Set<TrainerLinkStatus>? statuses});
    Stream<List<TrainerLink>> watchForTrainer(String trainerId, {Set<TrainerLinkStatus>? statuses});
  }
  ```
- Path Firestore: `trainer_links/{linkId}`. `linkId` auto-id (NO determinístico — un PF y atleta pueden haber tenido vínculos terminados que luego retoman, queremos historial separado).

**Providers**:
- `lib/features/coach/application/trainer_link_providers.dart`:
  - `trainerLinkRepositoryProvider`
  - `linksForTrainerProvider` (`FutureProvider.autoDispose.family<List<TrainerLink>, String>`)
  - `linksForAthleteProvider` (mismo patrón)
  - `currentAthleteLinkProvider` (single active link del atleta actual)

**Firestore rules** (`firestore.rules`):
- Nueva sección para `trainer_links/{linkId}`:
  - `allow read: if auth.uid in [trainerId, athleteId]` (solo members)
  - `allow create: if auth.uid == athleteId` (solo athlete inicia request)
  - `allow update: if auth.uid in [trainerId, athleteId]` + validación de transiciones de status válidas
  - `allow delete: if false` (terminate = update status, no se borran)
- Actualización de `routines/{routineId}`:
  - `allow read: if visibility == 'public' OR auth.uid == assignedTo OR auth.uid == assignedBy`
  - `allow write: if false` (sigue siendo seed-only; create por PF llega en Etapa 4)

**Migration script** (`scripts/backfill_coach_foundations.js`):
- Recorre `routines/` y agrega `source: 'system'` + `visibility: 'public'` a las que no lo tengan.
- Idempotente (skip si ya tiene los fields).
- Se corre 1 vez post-deploy. NO bloquea el merge — los modelos default a los mismos valores si los fields faltan.

### Test deliverables

- `test/features/profile/domain/user_profile_test.dart` — agrega 2-3 scenarios para los nuevos fields trainer (defaults nulos, round-trip JSON).
- `test/features/workout/domain/routine_test.dart` — agrega scenarios para source/visibility/assignedBy/assignedTo (defaults system/public, round-trip).
- `test/features/coach/domain/trainer_link_test.dart` (nuevo) — model tests (status enum, ==, round-trip).
- `test/features/coach/data/trainer_link_repository_test.dart` (nuevo) — fake firestore tests para los 6 métodos públicos.
- `test/features/coach/application/trainer_link_providers_test.dart` (nuevo) — provider tests con mocktail.

---

## 3. How

### Order de implementación

1. **UserProfile extension** — additive nullable fields. Sin riesgo. Hot reload-safe.
2. **Routine extension** — fields adicionales con `@Default('system')` y `@Default('public')`. Los docs viejos en Firestore que no tengan estos campos van a deserializar a los defaults. Backfill es nice-to-have para data consistency, no bloqueante.
3. **TrainerLink model** — nuevo archivo, sin riesgo.
4. **TrainerLinkRepository** — nuevo archivo. Implementa los 6 métodos. Cada uno: read/write a `trainer_links/{linkId}`.
5. **Providers** — wire up del repo + family providers para listas.
6. **Firestore rules** — escribir + deploy via `firebase deploy --only firestore:rules --project treino-dev`.
7. **Backfill script** — opcional, correr post-deploy.
8. **Tests** — al menos uno por método público del repo + smoke por modelo.

### Routine enum encoding

Para los 2 enums nuevos (`RoutineSource`, `RoutineVisibility`), uso el mismo patrón que `SessionStatus`: enum + extension con `_wireMap` para fromJson/toJson, y default value via `@Default('system')` / `@Default('public')` en el freezed model.

```dart
enum RoutineSource { system, trainerAssigned, userCreated }

extension RoutineSourceX on RoutineSource {
  String toJson() => switch (this) {
    RoutineSource.system => 'system',
    RoutineSource.trainerAssigned => 'trainer-assigned',
    RoutineSource.userCreated => 'user-created',
  };
  static RoutineSource fromJson(String s) => switch (s) {
    'system' => RoutineSource.system,
    'trainer-assigned' => RoutineSource.trainerAssigned,
    'user-created' => RoutineSource.userCreated,
    _ => RoutineSource.system, // defensivo
  };
}
```

Idem para `RoutineVisibility { public, private, shared }`.

### TrainerLink state transitions

Estados válidos y transiciones:

```
[create] ──► pending ──► active ──► paused ◄──► active ──► terminated
                ├──► terminated (decline)         └────► terminated
                └──► (no path back from terminated)
```

- `request` crea con `status: pending`.
- `accept` exige `status == pending` → setea `status: active`, `acceptedAt: now`.
- `decline` exige `status == pending` → setea `status: terminated`, `terminatedAt: now`, `terminationReason: 'declined'`.
- `terminate` exige `status in [active, paused]` → setea `status: terminated`, `terminatedAt: now`.
- (paused/resume queda para iteración futura — no en MVP de Etapa 1).

Validación en Firestore rules vía `request.resource.data.status` checks.

### Geohash deferred

`trainerGeohash` se agrega como `String?` field pero NADIE lo escribe en Etapa 1. Etapa 2 (Discovery) computa el geohash client-side cuando el PF setea su `trainerLocation`, usando el package `geoflutterfire2`. Etapa 1 solo deja el campo listo en el schema.

---

## 4. Trade-offs aceptados (4 decisiones)

| # | Decisión | Rationale |
|---|---|---|
| 1 | **`trainer_links/{linkId}` auto-id** (no determinístico) | Un PF y atleta pueden tener vínculos múltiples si terminaron uno y arrancan otro. Auto-id deja historial separado. Trade-off: queries "¿existe vínculo activo entre X y Y?" requieren `where`, no `get(docRef)`. Aceptado. |
| 2 | **Routine defaults `source='system'`, `visibility='public'`** | Retro-compat — todos los docs seedeados sin estos fields siguen funcionando como plantillas públicas. Backfill es nice-to-have, no bloqueante. |
| 3 | **`trainerSpecialty: String?` (no enum) en Etapa 1** | El catálogo de especialidades (fuerza, hipertrofia, crossfit, calistenia, running, yoga, etc.) lo definimos cuando arranque Etapa 2 (Discovery) con visibilidad de cómo se filtra. Por ahora String libre. |
| 4 | **`request` solo desde athlete-side** (no permite que el PF inicie) | Convención producto: el cliente busca al PF, no al revés. Si en el futuro queremos onboarding "el PF invita a su alumno", agregamos un endpoint `invite` separado. |

---

## 5. Out of scope

| Item | Lands en |
|---|---|
| Onboarding del PF (extender ProfileSetup con campos trainer-specific) | Etapa 2 (Discovery) — incluye UI para que el PF setee bio/specialty/location |
| Cómputo de geohash al setear location | Etapa 2 (Discovery) |
| UI de "Mis solicitudes" / "Mis alumnos" / "Mi PF" | Etapa 3 (Link lifecycle) |
| Permisos del PF sobre el historial del atleta | Etapa 2 o 3 — campo `sharedWithTrainer: bool` en TrainerLink (open question del roadmap) |
| Notifications cuando se acepta/rechaza/termina un vínculo | Fase 6 (push notifications) |
| Paused / Resume del vínculo | Iteración futura — Etapa 1 deja el status `paused` definido pero no expone APIs específicas |

---

## 6. Success criteria

- [ ] `UserProfile.toJson() / fromJson()` round-trip preserva los 5 nuevos campos trainer y los maneja como nulls cuando ausentes
- [ ] `Routine.toJson() / fromJson()` round-trip preserva source/visibility/assignedBy/assignedTo; docs sin estos fields default a `source=system, visibility=public`
- [ ] `TrainerLink` round-trip JSON
- [ ] `TrainerLinkRepository.request(trainerId, athleteId)` crea doc con `status: pending`, `requestedAt: now`
- [ ] `accept` transiciona pending → active, setea acceptedAt
- [ ] `decline` transiciona pending → terminated con `terminationReason: 'declined'`
- [ ] `terminate` transiciona active/paused → terminated, setea terminatedAt
- [ ] `listForTrainer / listForAthlete` filtran por status opcional
- [ ] `watchForTrainer` emite cambios real-time vía snapshot
- [ ] Firestore rules: cross-user read de `trainer_links` bloqueado; non-member create bloqueado; auth=trainerId create bloqueado (solo athlete inicia)
- [ ] Firestore rules: Routine privada solo accesible para assignedBy/assignedTo
- [ ] `flutter analyze` 0 issues
- [ ] `dart format` clean
- [ ] Tests pasan (incluyendo los nuevos)
- [ ] No regresiones en tests existentes (Fase 1-4)

---

## 7. Risks

| # | Riesgo | Mitigación |
|---|---|---|
| 1 | Cambio en `Routine` model rompe deserialization de docs viejos | Defaults `@Default('system')` y `@Default('public')` cubren el caso — docs sin campos parsean OK. Test explícito de round-trip con JSON sin los campos nuevos. |
| 2 | Firestore rules con OR clauses son delicadas (read condicional por visibility) | Tests via `scripts/rules_test/` con casos: user en assignedTo, otro user, sin auth. Antes de deploy en prod. |
| 3 | El backfill script puede afectar producción si lo corremos contra el proyecto wrong | Hardcoded check `--project treino-dev` y warning en stdout. Dry-run mode (`--dry`) que solo printea sin escribir. |
| 4 | Geohash queda definido como campo pero sin lógica → Etapa 2 podría descubrir que el tipo de dato no sirve | Riesgo bajo: geohash es siempre String. El package `geoflutterfire2` produce String. Acceptable. |
| 5 | TrainerLink estados duros de testear | fake_cloud_firestore cubre OK. Test transitions de estado válido + tests negativos (intentar accept sobre terminated, etc.) |

---

## 8. LOC estimate

| Bucket | LOC aprox |
|---|---|
| UserProfile + Routine extensions | ~30 |
| TrainerLink model + extension | ~80 |
| TrainerLinkRepository | ~150 |
| Providers | ~50 |
| Firestore rules updates | ~40 |
| Backfill script | ~50 |
| Tests (model + repo + provider) | ~400 |
| **Total** | **~800** |

~400 LOC producción + ~400 tests. Single PR razonable con `size:exception` (justificado por cohesión — son las foundations indivisibles).
