# Exploration: coach-discovery (Fase 5 · Etapa 2)

**Change name**: coach-discovery
**Fase/Etapa**: Fase 5 · Etapa 2
**Branch target**: feat/coach-discovery
**Project**: treino
**Artifact store**: hybrid (openspec + engram)
**Engram key**: sdd/coach-discovery/explore
**SCENARIO start**: 407

---

## Estado actual del codebase

### Etapa 1 entregada (en main)

- `lib/features/profile/domain/user_profile.dart` — `UserProfile` extendido con: `trainerBio?`, `trainerSpecialty?`, `trainerLatitude: double?`, `trainerLongitude: double?`, `trainerGeohash: String?`, `trainerHourlyRate: int?`. NOTA: la ubicación está almacenada como lat/lon doubles separados, NO como `GeoPoint`.
- `lib/features/coach/domain/trainer_link.dart` — modelo `TrainerLink` (freezed) completo.
- `lib/features/coach/data/trainer_link_repository.dart` — `TrainerLinkRepository` con request/accept/decline/terminate/listForTrainer/listForAthlete/watchForTrainer.
- `lib/features/coach/application/trainer_link_providers.dart` — providers Riverpod para vínculos.
- `firestore.rules` — reglas para `trainer_links/**` y `routines` con visibility filter.

### UI existente relevante

- `lib/features/coach/coach_screen.dart` — dispatcher athlete vs trainer.
- `lib/features/coach/athlete_coach_view.dart` — stub. Esta etapa lo REEMPLAZA con `TrainersListScreen`.
- `lib/features/feed/presentation/public_profile_screen.dart` — usa `PublicProfileHero`, `PublicProfileFollowButton`, `PublicProfileStatsRow`.
- `lib/features/feed/presentation/widgets/user_search_result_tile.dart` — buen patrón de referencia para `TrainerListTile`.
- `lib/app/router.dart` — `/coach` está bajo ShellRoute.

### Infraestructura de datos públicos

- `userPublicProfiles/{uid}` — colección con `uid, displayName, displayNameLowercase, avatarUrl, gymId`. Readable por cualquier usuario autenticado. **No contiene campos de trainer**.
- `users/{uid}` — owner-only read. **Los trainer fields (geohash, specialty, etc.) viven acá pero NO son queryables desde otros usuarios.**

---

## BLOQUEADOR CRÍTICO: Firestore Rules

La query propuesta en el roadmap:
```
users.where('role','==','trainer').where('trainerGeohash', isGreaterThan, prefix)...
```
**FALLA en runtime**. La regla de `users/{uid}` es owner-only.

Este es el MISMO anti-pattern que rompió Fase 3 Etapa 5. La solución documentada en Fase 3 Etapa 5.5 fue crear `userPublicProfiles` como colección separada.

**Solución requerida**: Crear `trainerPublicProfiles/{uid}` con los campos públicos para discovery: `uid, displayName, displayNameLowercase, avatarUrl, trainerSpecialty, trainerGeohash, trainerLatitude, trainerLongitude, trainerHourlyRate`. Dual-write desde `UserRepository.update()` vía `WriteBatch` (mismo patrón que `_publicFields` para `userPublicProfiles`).

---

## Decisiones resueltas

**D1 — Geohash prefix length: geohash5 (~5km cells)**
Radio de búsqueda ~10-15km. Geohash6 requeriría multi-query de vecinos — innecesario para MVP urbano.

**D2 — Fuente de ubicación del atleta: device GPS via `geolocator`**
El UserProfile del atleta no tiene campos de ubicación propia. Fallback sin permiso: lista sin filtro geográfico.

**D3 — Specialty filter: lista predefinida**
`powerlifting | crossfit | bodybuilding | hipertrofia | wellness | kinesiología | funcional | running | yoga | calistenia`. Evita fragmentación de strings.

**D4 — No-location fallback: todos los trainers, ordenados por displayName**
Coincide con cross-cutting concern del roadmap.

**D5 — Empty/Loading/Error states: patrones existentes (HistorialSection / PublicProfileScreen)**

**D7 — CTA "PEDIR VÍNCULO": stub con SnackBar**
Botón activo (no disabled) para mostrar UI completa. Tap → SnackBar "Próximamente — Etapa 3". El real (call a `TrainerLinkRepository.request()`) llega en Etapa 3.

**D8 — Widgets reutilizables**:
- `PostAvatar` — SÍ reutilizar.
- `PublicProfileHero`, `PublicProfileStatsRow` — NO reutilizar (acoplados a athlete schema).
- Crear `TrainerProfileHero`, `TrainerStatsRow`, `TrainerSpecialtyChip` propios.

**D9 — Router: `/coach/trainer/:uid` bajo ShellRoute** (mismo patrón que `/feed/profile/:uid`).

**D10 — Distancia "X km" en cards: sí, haversine client-side.**

**D11 — Añadir `geolocator: ^13.0.0` a pubspec.yaml**
+ Info.plist `NSLocationWhenInUseUsageDescription` + AndroidManifest `ACCESS_FINE_LOCATION`.

**D12 — Nueva colección `trainerPublicProfiles`** con `allow read: auth != null`. Dual-write atómico desde UserRepository.

**D13 — Mockup muestra vista mapa + rating, pero scope Etapa 2 = solo lista**.
Toggle mapa = stub "Próximamente". Rating/reviews = placeholder "–" (Reviews queda para Fase 5.5 o 6).

**D14 — Rating/Reseñas: fuera de scope** (roadmap: "eventualmente, pero no MVP").

---

## Áreas afectadas

### Archivos nuevos

```
lib/features/coach/
  presentation/
    trainers_list_screen.dart
    trainer_public_profile_screen.dart
    widgets/
      trainer_list_tile.dart
      trainer_profile_hero.dart
      trainer_stats_row.dart
      trainer_specialty_chips.dart
      trainer_contact_cta_stub.dart
  application/
    trainer_discovery_providers.dart
  data/
    trainer_public_profile_repository.dart
  domain/
    trainer_public_profile.dart (+ .freezed.dart + .g.dart)
    trainer_specialty.dart
    coach_strings.dart

lib/core/utils/
  haversine.dart

firestore.rules                          # Añadir regla trainerPublicProfiles
```

### Archivos modificados

```
lib/features/coach/athlete_coach_view.dart      # Reemplazar stub por TrainersListScreen
lib/app/router.dart                              # Añadir /coach/trainer/:uid
lib/features/profile/data/user_repository.dart   # Dual-write a trainerPublicProfiles
lib/core/widgets/treino_icon.dart                # Añadir iconos (specialty, money)
pubspec.yaml                                     # Añadir geolocator
ios/Runner/Info.plist                            # NSLocationWhenInUseUsageDescription
android/app/src/main/AndroidManifest.xml         # ACCESS_FINE_LOCATION
```

### Sin tocar

- `public_profile_screen.dart` y sus widgets
- `coach_screen.dart`, `trainer_coach_view.dart`
- `trainer_link_repository.dart` (read-only consumer en esta etapa)

---

## Aproximaciones

| Aproximación | Pros | Cons |
|---|---|---|
| **A: Nueva colección `trainerPublicProfiles`** (RECOMENDADA) | Patrón idéntico a `userPublicProfiles` (probado en Fase 3 Etapa 5.5). Privacy separation. Atomic dual-write via WriteBatch. | Modelo + repo nuevos. Esfuerzo medio. |
| B: Extender `userPublicProfiles` con campos trainer | Sin modelo nuevo. | Rompe boundary de "public identity" — exponer hourlyRate en el perfil público de cualquier usuario es deuda arquitectónica. |

**Decisión**: A.

---

## Riesgos

1. **Trainers sin geohash seteado**: los trainers de Etapa 1 todavía no completaron onboarding extendido. Para testing: seedear 3-5 trainers con `trainerGeohash` populated. Fallback en producción: si no hay matches en la región → mostrar todos sin filtro geográfico.

2. **geolocator permission UX**: primer uso de tab Coach pide permiso. Mostrar rationale ANTES del system dialog ("Para encontrar PFs cerca tuyo necesitamos tu ubicación").

3. **PR size ~400-600 líneas**: chained PRs recomendados.
   - **PR1**: infra (modelo + colección + rule + UserRepository dual-write + geolocator setup + iOS/Android manifests).
   - **PR2**: UI (TrainersListScreen + TrainerPublicProfileScreen + router).

4. **Mockup delta**: mapa view + rating system son out-of-scope. Documentar explícitamente como stubs en spec.

5. **Etapa 3 dependency**: CTA "PEDIR VÍNCULO" es stub. Comunicar a QA.

---

## SCENARIO start

**407** (último usado en main: 406)

---

## Listo para Proposal

**SÍ**, con estas aclaraciones para el proposal:

1. Query DEBE ir a `trainerPublicProfiles` (nueva colección), no a `users` — bloqueante crítico.
2. `geolocator` se añade a pubspec + permisos iOS/Android.
3. `UserProfile` usa `trainerLatitude/Longitude: double?`, no `GeoPoint`.
4. Mapa view + rating quedan como stubs documentados.
5. Chained PRs (infra + UI).
