# Proposal: Coach Discovery

**Change**: `coach-discovery`
**Fase / Etapa**: Fase 5 · Etapa 2
**Branch (target)**: chained PRs — `feat/coach-discovery-infra` (PR1) + `feat/coach-discovery-ui` (PR2)
**Owner**: Dev A (Martín)
**Project**: treino
**Artifact store**: hybrid
**Strict TDD**: ACTIVE (`flutter test`)
**SCENARIO start**: 407
**REQ namespace**: `REQ-COACH-DISC-NNN`

## Intent

Reemplazar el stub `AthleteCoachView` por una experiencia real de descubrimiento de Personal Trainers: lista filtrable por especialidad y ordenada por distancia (haversine client-side) sobre una nueva colección pública `trainerPublicProfiles`, más una pantalla de perfil público del trainer con hero, stats placeholder y CTA "PEDIR VÍNCULO" stub (la solicitud real llega en Etapa 3). La infraestructura introduce dual-write atómico en `UserRepository.update()` para mantener `trainerPublicProfiles` sincronizado con el `users/{uid}` privado del trainer, replicando el patrón ya probado en Fase 3 Etapa 5.5 (`userPublicProfiles`). Se cierra así el primer flujo end-to-end de "athlete encuentra PF" sin tocar todavía el sistema de vínculos, ratings o vista mapa — todos delimitados como out-of-scope explícito.

## Scope

### In Scope

**PR1 — Infra (`feat/coach-discovery-infra`)**:
- Modelo `TrainerPublicProfile` (freezed) en `lib/features/coach/domain/`: `uid, displayName, displayNameLowercase, avatarUrl?, trainerSpecialty, trainerGeohash, trainerLatitude, trainerLongitude, trainerHourlyRate`.
- Enum/sealed `TrainerSpecialty` con lista predefinida (10 valores: `powerlifting | crossfit | bodybuilding | hipertrofia | wellness | kinesiología | funcional | running | yoga | calistenia`).
- Repository `TrainerPublicProfileRepository` en `lib/features/coach/data/` con `queryByGeohashPrefix(prefix)` y `getByUid(uid)`.
- Util `lib/core/utils/haversine.dart` con `haversineKm(lat1, lon1, lat2, lon2) → double`.
- `firestore.rules`: nueva regla `match /trainerPublicProfiles/{uid}` con `allow read: if request.auth != null` y `allow write: if request.auth.uid == uid`.
- `UserRepository.update()` extendido con dual-write atómico vía `WriteBatch` cuando se detecten cambios en cualquier `trainerField`. Idempotente y atómico (toda la transacción falla si una escritura falla).
- `pubspec.yaml`: `geolocator: ^13.0.0`.
- `ios/Runner/Info.plist`: `NSLocationWhenInUseUsageDescription` con copy en español.
- `android/app/src/main/AndroidManifest.xml`: permiso `ACCESS_FINE_LOCATION`.
- Tests SCENARIO-407+: modelo (fromMap/toMap, equality), repo (query prefix, fallback empty, getByUid), haversine (casos conocidos), UserRepository dual-write (batch atómico, no-op cuando no cambian trainer fields), Firestore rules (read auth, write owner-only).

**PR2 — UI (`feat/coach-discovery-ui`)**:
- `TrainersListScreen` en `lib/features/coach/presentation/`: reemplaza el stub `AthleteCoachView`. Header con chips de especialidad (filter pills), lista de `TrainerListTile` ordenada por distancia ascendente.
- `TrainerListTile` widget: avatar (`PostAvatar` reutilizado), nombre, especialidad chip, distancia "X km", precio/mes "$X / mes". Tap → `context.push('/coach/trainer/:uid')`.
- `TrainerPublicProfileScreen` en `lib/features/coach/presentation/`: `TrainerProfileHero` (full-bleed avatar + nombre + especialidad), `TrainerStatsRow` (3 stats: RESEÑAS placeholder "–", AÑOS EXP placeholder "–", ALUMNOS placeholder "–"), bio (si existe), `TrainerSpecialtyChip` list, `TrainerContactCtaStub` (botón "PEDIR VÍNCULO" → `SnackBar('Próximamente — Etapa 3')`).
- Provider `trainerDiscoveryProviders.dart`: `currentLocationProvider` (geolocator), `trainerSearchProvider(specialty?)` que combina geohash query + haversine sort + specialty filter.
- `lib/app/router.dart`: sub-route `trainer/:uid` bajo el GoRoute de `/coach` (ShellRoute, mismo patrón que `/feed/profile/:uid`).
- `WorkoutStrings`/`CoachStrings`: copy centralizado (filtros, empty states, CTA stub).
- `treino_icon.dart`: nuevos iconos (`specialty`, `money`, `star`).
- Vista Mapa = stub "Próximamente" (toggle visible pero no implementado).
- Rating/reviews = placeholder "–" en cards y profile.
- Fallback no-location: lista completa sin filtro de distancia, ordenada por displayName.
- Permission rationale: bottom sheet ANTES del system dialog ("Para encontrar PFs cerca tuyo necesitamos tu ubicación").
- Tests SCENARIO ~418+: widget tests para `TrainersListScreen` (lista, filter chips, empty, fallback sin location, tap nav), widget tests para `TrainerPublicProfileScreen` (header, stats placeholder, CTA stub muestra SnackBar), router test para `/coach/trainer/:uid`, provider test para `trainerSearchProvider` (mock geohash + haversine sort).

### Out of Scope (DELIBERATELY STUBBED — documentar en QA)

- **Vista Mapa**: el mockup muestra mapa radar con pins de precios. Esta etapa solo entrega vista Lista. El toggle Mapa/Lista en header existe visualmente pero al tap "Mapa" muestra `Center(Text('Próximamente'))`. Implementación real queda para una etapa futura (no en roadmap activo).
- **Rating / reseñas**: el mockup muestra "4.9 ★ (94 reseñas)". El sistema de reviews queda diferido a **Fase 5.5 o Fase 6**. En cards y profile se muestra placeholder "–" en lugar de número.
- **CTA "PEDIR VÍNCULO" real**: el botón se renderiza activo (no disabled, no invisible) por consistencia visual con el mockup. Al tap dispara `SnackBar('Próximamente — Etapa 3')`. La llamada real a `TrainerLinkRepository.request()` llega en **Etapa 3** (vínculos).
- **Onboarding extendido del trainer**: esta etapa NO implementa el flujo donde el PF carga su especialidad, ubicación, hourlyRate. Asume que esos datos pueden estar nulos en producción (fallback) y se seedearán manualmente para testing/alfa.
- **Sistema de pagos / suscripciones**: el "$X / mes" es informativo, no transaccional.
- **Editar perfil público del trainer**: sin UI esta etapa. El dual-write se activa cuando exista la UI de edición (futura).
- **Cambios al sistema de vínculos**: `TrainerLinkRepository` queda intacto (read-only consumer en próxima etapa).
- **Cambios a `userPublicProfiles`**: privacy boundary preservado — no se mezclan campos de trainer en la colección pública genérica.

## Approach

### Problema central: Firestore rules bloquean la query directa

El roadmap original sugería `users.where('role','==','trainer').where('trainerGeohash', isGreaterThan, prefix)`. Esta query **FALLA en runtime**: la regla de `users/{uid}` es owner-only (`allow read: if request.auth.uid == uid`). Ningún atleta puede listar la colección `users`. Es el mismo anti-pattern que rompió Fase 3 Etapa 5 (search de usuarios), resuelto en Etapa 5.5 creando `userPublicProfiles` como colección separada con `read: auth != null`.

### Solución: colección pública dedicada + dual-write

Se crea `trainerPublicProfiles/{uid}` como colección Firestore separada con los campos públicos necesarios para discovery. Regla: `read: auth != null`, `write: owner-only`. `UserRepository.update()` se extiende para detectar cambios en cualquier `trainerField` (`displayName, avatarUrl, trainerSpecialty, trainerGeohash, trainerLatitude, trainerLongitude, trainerHourlyRate`) y ejecutar dual-write atómico via `WriteBatch`. Esto replica el patrón ya battle-tested en Fase 3 Etapa 5.5 con `userPublicProfiles._publicFields`.

### Discovery query: geohash5 prefix + haversine sort

- **Geohash5** (~5km cells, radio útil ~10-15km): una sola query con prefix range (`isGreaterThanOrEqualTo: prefix, isLessThan: prefix + ''`). Geohash6 requeriría multi-query de 9 vecinos para evitar boundary gaps — innecesariamente complejo para MVP urbano.
- **Athlete location**: device GPS via `geolocator: ^13.0.0`. Permiso solicitado con rationale ANTES del system dialog. Fallback sin permiso → lista completa ordenada por `displayName`.
- **Haversine sort client-side**: cálculo matemático trivial por card. Distancia "X km" se computa una sola vez por trainer y se incluye en el view-model del tile.
- **Specialty filter**: chips client-side sobre el result set ya devuelto por la query geohash (no se filtra en Firestore para no requerir compound index `trainerGeohash + trainerSpecialty`).

### UI: list-only + stubs explícitos

La vista Lista es el core. El toggle Mapa queda como stub `Próximamente` para no romper la affordance visual del mockup. Rating placeholder "–" (no se muestra "0 ★" para no confundir). CTA "PEDIR VÍNCULO" stub con SnackBar — el botón está activo visualmente porque es la entry point de Etapa 3 y se quiere validar el layout completo del profile.

### Router: sub-route bajo ShellRoute

`/coach/trainer/:uid` se monta bajo el GoRoute existente de `/coach`, manteniendo bottom bar visible. Patrón idéntico a `/feed/profile/:uid` (definido en Fase 3 Etapa 5).

## Capabilities

### New Capabilities

- **`coach-discovery-data`**: nueva capability documentando el modelo `TrainerPublicProfile`, el repositorio `TrainerPublicProfileRepository`, la colección Firestore `trainerPublicProfiles` con sus rules, y la lógica de dual-write desde `UserRepository`. Incluye el util `haversineKm` por ser dependencia transversal del discovery flow.
- **`coach-discovery-ui`**: nueva capability documentando `TrainersListScreen`, `TrainerPublicProfileScreen`, widgets reutilizables (`TrainerListTile`, `TrainerProfileHero`, `TrainerStatsRow`, `TrainerSpecialtyChip`, `TrainerContactCtaStub`), providers (`currentLocationProvider`, `trainerSearchProvider`) y el sub-route `/coach/trainer/:uid`.

### Modified Capabilities

- **`user-data`**: anotación documental — `UserRepository.update()` ahora detecta cambios en `trainerFields` y dispara dual-write atómico contra `trainerPublicProfiles` vía `WriteBatch`. Se preserva la semántica existente del dual-write a `userPublicProfiles` (no se mezclan, son dos batches lógicos dentro del mismo WriteBatch). La extensión es aditiva: si el user no es trainer o no cambia ningún `trainerField`, el comportamiento es idéntico al actual.

## Affected Areas

| Area | Impact | PR | Description |
|------|--------|-----|-------------|
| `lib/features/coach/domain/trainer_public_profile.dart` (+ `.freezed.dart`, `.g.dart`) | New | PR1 | Modelo freezed + JSON serialization. |
| `lib/features/coach/domain/trainer_specialty.dart` | New | PR1 | Enum con 10 valores predefinidos. |
| `lib/features/coach/data/trainer_public_profile_repository.dart` | New | PR1 | Query geohash prefix + getByUid. |
| `lib/features/coach/domain/coach_strings.dart` | New | PR1/PR2 | Copy centralizado del módulo Coach. |
| `lib/core/utils/haversine.dart` | New | PR1 | Util matemático. |
| `lib/features/profile/data/user_repository.dart` | Modified | PR1 | Dual-write atómico a `trainerPublicProfiles`. |
| `firestore.rules` | Modified | PR1 | Nueva regla `trainerPublicProfiles`. |
| `pubspec.yaml` | Modified | PR1 | `geolocator: ^13.0.0`. |
| `ios/Runner/Info.plist` | Modified | PR1 | `NSLocationWhenInUseUsageDescription`. |
| `android/app/src/main/AndroidManifest.xml` | Modified | PR1 | `ACCESS_FINE_LOCATION`. |
| `lib/features/coach/presentation/trainers_list_screen.dart` | New | PR2 | Pantalla lista filtrable. |
| `lib/features/coach/presentation/trainer_public_profile_screen.dart` | New | PR2 | Perfil público del trainer. |
| `lib/features/coach/presentation/widgets/trainer_list_tile.dart` | New | PR2 | Card del trainer. |
| `lib/features/coach/presentation/widgets/trainer_profile_hero.dart` | New | PR2 | Hero del profile. |
| `lib/features/coach/presentation/widgets/trainer_stats_row.dart` | New | PR2 | 3 stats placeholder. |
| `lib/features/coach/presentation/widgets/trainer_specialty_chips.dart` | New | PR2 | Chips reutilizables. |
| `lib/features/coach/presentation/widgets/trainer_contact_cta_stub.dart` | New | PR2 | CTA con SnackBar stub. |
| `lib/features/coach/application/trainer_discovery_providers.dart` | New | PR2 | Providers Riverpod. |
| `lib/features/coach/athlete_coach_view.dart` | Modified | PR2 | Stub → render `TrainersListScreen`. |
| `lib/app/router.dart` | Modified | PR2 | Sub-route `/coach/trainer/:uid`. |
| `lib/core/widgets/treino_icon.dart` | Modified | PR2 | Iconos adicionales (`specialty`, `money`, `star`). |
| `test/features/coach/**` | New | PR1+PR2 | SCENARIO-407..~430. |

## Rollback Plan

### Rollback de PR2 (UI) — bajo riesgo

Revert del commit de `feat/coach-discovery-ui`. La rama vuelve al estado post-PR1: `AthleteCoachView` muestra el stub antiguo nuevamente. La infraestructura (modelo, repo, regla Firestore, dual-write) queda en main pero queda "dormida" — no hay consumidores. Sin migraciones, sin impacto en producción. La colección `trainerPublicProfiles` queda creada y sigue recibiendo dual-writes (idempotente y harmless).

### Rollback de PR1 (Infra) — requiere revertir PR2 primero

Si PR2 ya está mergeado, **revertir PR1 sin revertir PR2 ROMPERÍA la app** (TrainersListScreen importa `TrainerPublicProfileRepository`). Orden obligatorio: revert PR2 → revert PR1. El revert de PR1 quita la regla Firestore, el dual-write y la dependencia geolocator. La colección `trainerPublicProfiles` queda en Firestore pero huérfana (sin escritores) — se puede limpiar manualmente o dejarla (no consume recursos significativos).

### Riesgo de rollback

- **PR2 revert**: nulo. Vuelve al estado pre-etapa.
- **PR1 revert** (con PR2 ya revertido): bajo. La regla Firestore se quita atomicamente; geolocator sale del pubspec; el dual-write se desactiva. Trainers que ya escribieron sus campos quedan con datos en `users/{uid}` intactos.

## Chained PR Plan

Estimación bruta del explore: ~400-600 líneas. Excede el budget de 400 → **Chained PRs (auto-chain)** confirmado por delivery strategy.

### PR1: `feat/coach-discovery-infra` (~250-320 líneas)

**Scope**:
- Modelo `TrainerPublicProfile` + `TrainerSpecialty` enum + `.freezed/.g`.
- Repository `TrainerPublicProfileRepository`.
- Util `haversineKm`.
- `firestore.rules` con regla nueva.
- `UserRepository.update()` extendido con dual-write atómico.
- `pubspec.yaml` + iOS `Info.plist` + Android `AndroidManifest.xml`.
- Tests: modelo, repo, haversine, dual-write batch, rules.

**Estado intermedio post-PR1 (entre merges)**: `athlete_coach_view.dart` **sigue mostrando el stub antiguo** ("COACH / Personal Trainers cerca tuyo"). El usuario athlete no ve cambio en la UI. La infra queda lista y testeada pero sin consumidores UI. Esto es **deliberado**: PR1 es self-contained y mergeable independientemente sin romper nada en producción.

**Entrega**: backend ready, sin UI nueva. La colección `trainerPublicProfiles` empieza a poblarse a medida que usuarios trainer editen su perfil (cuando la UI de edición exista — futuro). Para alfa: seed manual via Firebase Admin.

### PR2: `feat/coach-discovery-ui` (~280-350 líneas)

**Scope**:
- `TrainersListScreen` (reemplaza stub de `athlete_coach_view.dart`).
- `TrainerPublicProfileScreen`.
- Widgets: `TrainerListTile`, `TrainerProfileHero`, `TrainerStatsRow`, `TrainerSpecialtyChip`, `TrainerContactCtaStub`.
- Provider `trainerDiscoveryProviders.dart` (`currentLocationProvider`, `trainerSearchProvider`).
- Sub-route `/coach/trainer/:uid` en `router.dart`.
- `treino_icon.dart` iconos nuevos.
- Tests: widget tests de ambas pantallas, provider test, router test.

**Entrega**: UI completa end-to-end. Cierra la Etapa 2.

### Caveat del estado intermedio

Mientras PR1 está mergeado y PR2 no, la sección Coach del atleta sigue mostrando el stub viejo. Esto es **esperado** y no es un bug. La comunicación al equipo / QA debe ser explícita: "PR1 es infra-only, la UI llega en PR2". No hay path de usuario que rompa.

### Justificación del split

- PR1 puede mergearse independientemente sin romper producción (la infra queda dormida).
- PR2 depende mecánicamente de PR1 (importa el modelo y el repo) pero su rebase es trivial.
- Cada PR cierra una unidad lógica testeable.
- Tamaño individual queda dentro del budget de 400 LOC.
- Patrón ya validado: split por concern (data vs UI) usado en Dev B / session player y Fase 3 Etapa 5.5.

## SCENARIO Range Expected

- **PR1**: SCENARIO-407 → ~417 (≈10-11 scenarios entre modelo, repo, haversine, dual-write, rules).
- **PR2**: SCENARIO-418 → ~430 (≈12-13 scenarios entre list screen, profile screen, providers, router).
- **Total esperado**: SCENARIO-407 → ~430. Rango sujeto a ajuste fino en `sdd-tasks`.

## REQ Namespace

`REQ-COACH-DISC-NNN` (e.g. `REQ-COACH-DISC-001` = modelo `TrainerPublicProfile` campos, `REQ-COACH-DISC-002` = repo query geohash prefix, etc.). Numeración secuencial definida en `sdd-spec`.

## Dependencies

### Hard dependencies (must be merged before)

Fase 5 Etapa 1 — **ya mergeada en main**. Provee:
- `UserProfile` con campos trainer (`trainerBio?, trainerSpecialty?, trainerLatitude?, trainerLongitude?, trainerGeohash?, trainerHourlyRate?`).
- `TrainerLink` modelo + `TrainerLinkRepository` (read-only consumer en próxima etapa).
- `firestore.rules` para `trainer_links/**`.

### Soft dependencies (parallel, no conflict)

Ninguna. No hay otras feature branches en flight que toquen `UserRepository`, `firestore.rules`, `router.dart` ni `pubspec.yaml`.

### Downstream consumers (informativo)

- **Etapa 3 (vínculos)**: cablea `TrainerContactCtaStub` → llamada real a `TrainerLinkRepository.request()`.
- **Fase 5.5 / Fase 6 (reviews)**: llena el placeholder "–" de `TrainerStatsRow` con datos reales.
- **Etapa futura (mapa)**: implementa la vista mapa que hoy es stub `Próximamente`.

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Atleta sin permisos de ubicación queda sin discovery útil | Med | Fallback: lista completa sin filtro geográfico, ordenada por `displayName`. Rationale visible antes del system dialog. |
| Trainers de Etapa 1 sin `trainerGeohash` seteado → query devuelve vacío en alfa | High | Seed manual de 3-5 trainers con geohash via Firebase Admin para testing. Fallback en runtime si la query devuelve <N resultados → relajar filtro geográfico. |
| Dual-write race condition entre `users/{uid}` y `trainerPublicProfiles/{uid}` | Low | `WriteBatch` es atómico en Firestore. Test cubre el caso de falla parcial. |
| `geolocator: ^13.0.0` introduce break en iOS/Android build | Med | Probar build de release en ambas plataformas en PR1 antes de mergear. Documentar versión exacta. |
| PR1 mergeado y PR2 demorado → trainers escriben dual-write pero nadie consume | Low | Datos quedan en Firestore listos. No hay impacto negativo. Sólo desperdicio de writes (insignificante en alfa). |
| Mockup delta (mapa, rating) genera confusión en QA | Med | Out-of-scope documentado explícitamente en este proposal. Comunicar a QA: "vista Lista únicamente, rating = placeholder, CTA es stub". |
| `trainerSpecialty` legacy con strings free-form rompe enum parsing | Low | `TrainerSpecialty.fromString()` con fallback a `null` o categoría "otros". Documentar en design. |
| PR1 excede 400 LOC al sumar tests | Low | Estimado 250-320 con margen. Monitorear en `sdd-apply`. |
| PR2 excede 400 LOC al sumar 5 widgets nuevos + screens | Med | Estimado 280-350. Si excede, considerar split adicional (widgets en PR2a, screens en PR2b). Decisión en `sdd-tasks`. |

## Open Questions (surface to design / tasks)

1. **Seeding strategy de trainers de prueba con geohash**: ¿script en `tool/` o documentación manual? Probablemente script idempotente que escribe 5 trainers seed en emulator + opcional en prod-staging. **Diferido a design**.
2. **Date / distance formatting helper**: ¿se crea `lib/core/utils/formatters.dart` para "X km" o se mantiene inline en el tile? **Diferido a design**.
3. **`TrainerSpecialty.fromString()` fallback**: ¿retorna `null` o categoría sentinel "otros"? **Diferido a design**.
4. **Permission rationale UX**: ¿bottom sheet custom o `showDialog`? **Diferido a design** (probablemente bottom sheet siguiendo el design system).
5. **Ordering cuando hay empate de distancia**: tiebreaker por `displayName` o por `trainerHourlyRate`? **Diferido a design** (default: `displayName`).
6. **Should PR2 split further?** Si `sdd-tasks` proyecta >380 LOC en PR2, evaluar split widgets/screens. **Diferido a tasks**.

## Success Criteria

- [ ] PR1 mergeado: modelo + repo + rule + dual-write + geolocator + iOS/Android manifests, todos con tests verdes.
- [ ] PR2 mergeado: `TrainersListScreen` reemplaza el stub `AthleteCoachView`, `TrainerPublicProfileScreen` accesible vía `/coach/trainer/:uid`, CTA stub funcional con SnackBar.
- [ ] Discovery flow end-to-end: athlete con location → ve trainers en su geohash5, ordenados por distancia ascendente, puede filtrar por especialidad via chips.
- [ ] Fallback sin location: athlete ve lista completa ordenada por `displayName` sin error.
- [ ] Dual-write atómico verificable: editar campos trainer en `users/{uid}` propaga a `trainerPublicProfiles/{uid}` en el mismo batch.
- [ ] Mapa view = stub `Próximamente` visible (toggle inactivo funcionalmente).
- [ ] Rating placeholder "–" en cards y profile.
- [ ] CTA "PEDIR VÍNCULO" muestra SnackBar `Próximamente — Etapa 3`.
- [ ] `flutter analyze` 0 issues, `dart format .` clean, `flutter test` green en ambos PRs.
- [ ] Sin tocar `userPublicProfiles`, `TrainerLinkRepository`, `coach_screen.dart`, `trainer_coach_view.dart` ni la rule de `trainer_links/**`.
- [ ] iOS + Android release builds compilan con geolocator añadido.

## Ready for spec + design

**Sí** — todas las decisiones arquitectónicas críticas resueltas en explore (Firestore rules workaround, geohash5, geolocator, specialty enum, dual-write atómico, sub-route bajo ShellRoute, widgets nuevos vs reutilización, scope explícito de stubs). Tradeoffs abiertos delegados a design: seeding script vs manual, formatting helpers, tiebreaker de ordering, permission rationale UX, posible split adicional de PR2. `sdd-spec` y `sdd-design` pueden correr en paralelo.
