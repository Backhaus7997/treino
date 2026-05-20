# Design: Coach Discovery (Fase 5 · Etapa 2)

**Change**: `coach-discovery` · **Branches**: `feat/coach-discovery-infra` (PR1) + `feat/coach-discovery-ui` (PR2)
**SCENARIOs**: 407..~430 · **REQs**: `REQ-COACH-DISC-NNN`
**Owner**: Dev A (Martín) · **Project**: treino
**Artifact store**: hybrid · **Strict TDD**: ACTIVE (`flutter test`)
**Delivery**: chained PRs (PR1 infra, PR2 UI)

## Technical Approach

Resuelvo el bloqueador de Firestore rules (athletes no pueden listar `users`) creando una colección pública dedicada `trainerPublicProfiles/{uid}` y un dual-write atómico desde `UserRepository.update()` que replica EXACTAMENTE el patrón ya battle-tested para `userPublicProfiles` (Fase 3 Etapa 5.5). El discovery flow es: lazy permission rationale → device GPS via `geolocator` → geohash5 encoding inline → prefix-range query sobre `trainerPublicProfiles` → haversine reorder client-side → specialty filter client-side sobre el result set. Sin compound indexes, sin multi-query de vecinos, sin nuevas dependencias salvo `geolocator`.

Dos PRs encadenados: **PR1** entrega toda la infra (modelo, repo, util haversine, util geohash5 inline, dual-write extendido, rule Firestore, deps, manifests) con el `AthleteCoachView` sigue mostrando el stub viejo — la infra queda "dormida" pero testeada. **PR2** entrega la UI completa (`TrainersListScreen` + `TrainerPublicProfileScreen` + providers + router sub-route) reemplazando el stub.

## Data Flow — Discovery

    AthleteCoachView (PR2)
        └── TrainersListScreen (ConsumerStatefulWidget)
                │
                ├── initState: ref.read(athleteLocationProvider.notifier).requestIfNeeded(context)
                │      │
                │      ▼
                │   ┌──────────────────────────────────────────────┐
                │   │ AthleteLocationNotifier.requestIfNeeded()    │
                │   │   if (status == initial)                     │
                │   │     1. show LocationPermissionRationaleSheet │
                │   │     2. user taps "Aceptar"                   │
                │   │     3. await Geolocator.requestPermission()  │
                │   │     4. await Geolocator.getCurrentPosition() │
                │   │     5. state = AsyncData(Position)           │
                │   │   else if (denied) state = AsyncData(null)   │
                │   └──────────────────────────────────────────────┘
                │
                ├──(watch)── athleteLocationProvider ──► AsyncValue<Position?>
                ├──(watch)── selectedSpecialtyProvider ──► TrainerSpecialty?
                │
                └──(watch)── trainerDiscoveryProvider
                        │
                        │ inside provider:
                        │   final location = ref.watch(athleteLocationProvider).valueOrNull;
                        │   final specialty = ref.watch(selectedSpecialtyProvider);
                        │   final repo = ref.watch(trainerPublicProfileRepositoryProvider);
                        │
                        │   List<TrainerPublicProfile> trainers;
                        │   if (location != null) {
                        │     final prefix = geohash5(location.latitude, location.longitude);
                        │     trainers = await repo.queryByGeohashPrefix(prefix);
                        │   } else {
                        │     trainers = await repo.listAllOrderedByDisplayName(limit: 50);
                        │   }
                        │
                        │   // Specialty filter client-side (avoids compound index).
                        │   if (specialty != null) {
                        │     trainers = trainers.where((t) => t.trainerSpecialty == specialty).toList();
                        │   }
                        │
                        │   // Haversine reorder client-side when location is known.
                        │   if (location != null) {
                        │     trainers.sort((a, b) {
                        │       final da = haversineKm(location.lat, location.lon, a.lat, a.lon);
                        │       final db = haversineKm(location.lat, location.lon, b.lat, b.lon);
                        │       return da.compareTo(db);
                        │     });
                        │   }
                        │   return trainers;
                        │
                        ├── AsyncLoading  ─► _ListLoadingState
                        ├── AsyncError    ─► _ListErrorState (retry: invalidate)
                        └── AsyncData(List<TrainerPublicProfile>)
                                          │
                                  ┌───────┴───────┐
                               empty           non-empty
                                  │               │
                                  ▼               ▼
                            _ListEmptyState   ListView.builder(TrainerListTile × N)

## Data Flow — Trainer Profile

    /coach/trainer/:uid (sub-route bajo ShellRoute)
        │
        ▼
    TrainerPublicProfileScreen (ConsumerWidget, requires uid)
        │
        ├──(watch)── trainerByIdProvider(uid) ──► AsyncValue<TrainerPublicProfile?>
        │                   │
        │                   ├── AsyncLoading ─► _ProfileLoadingState
        │                   ├── AsyncError   ─► _ProfileErrorState (retry)
        │                   └── AsyncData
        │                          │
        │                  trainer == null
        │                  ┌───────┴───────┐
        │                yes              no
        │                  ▼               ▼
        │           _ProfileNotFound   _ProfileLoaded(trainer)
        │                                  │
        │                                  ├── TrainerProfileHero(avatarUrl, displayName, specialty)
        │                                  ├── TrainerStatsRow (3 placeholder stats: "–")
        │                                  ├── bio (if trainerBio != null)
        │                                  ├── TrainerSpecialtyChips (single chip, profile mode)
        │                                  ├── hourlyRate display ("$X / mes")
        │                                  └── TrainerContactCtaStub ("PEDIR VÍNCULO")
        │                                          │
        │                                          └── onTap → SnackBar("Próximamente — Etapa 3")
        │
        └── back arrow → context.canPop() ? pop() : go('/coach')

## Data Flow — Dual-Write (UserRepository.update extension)

    UserRepository.update(uid, partial)
        │
        ├── 1. sanitize: drop immutable fields, set updatedAt
        ├── 2. publicSubset = _publicSubsetFromPartial(partial)         [existing]
        ├── 3. trainerPublicSubset = _trainerPublicSubsetFromPartial(partial)  [NEW]
        │         (returns null if no trainer field present)
        │
        ├── case A: publicSubset == null && trainerPublicSubset == null
        │           → single .set(users/uid, sanitized)                  [unchanged path]
        │
        └── case B/C/D: at least one subset is non-null
                  │
                  ▼
              WriteBatch:
                  batch.set(users/uid, sanitized, merge)
                  if (publicSubset != null) batch.set(userPublicProfiles/uid, publicSubset, merge)
                  if (trainerPublicSubset != null) batch.set(trainerPublicProfiles/uid, trainerPublicSubset, merge)
              await batch.commit()

**Atomic semantics**: si una de las escrituras falla, todo el batch falla y la transacción se aborta. No hay estado intermedio observable. Mismo contrato que el dual-write actual a `userPublicProfiles`.

## Architecture Decisions

| # | Decision | Choice | Rejected | Rationale |
|---|----------|--------|----------|-----------|
| 1 | `TrainerPublicProfile` field set | `uid, displayName, displayNameLowercase, avatarUrl?, trainerBio?, trainerSpecialty?, trainerGeohash?, trainerLatitude?, trainerLongitude?, trainerHourlyRate?` | Solo campos discovery-críticos (excluir bio) | Incluir `trainerBio` permite renderizar el profile screen con UNA sola lectura (`trainerByIdProvider`). Excluirlo forzaría un segundo read a `users/{uid}` que está bloqueado por owner-only rule. Privacy: bio del trainer es PÚBLICA por definición (la usa para vender sus servicios). hourlyRate también es público en este modelo. Lo único privado del trainer queda en `users/{uid}`: email, gender, bodyWeight, height, bornAt. |
| 2 | Dual-write trigger en `UserRepository.update()` | Diff por presencia de keys en `partial` (NO comparar valor viejo vs nuevo) | (a) Always-write para role==trainer; (b) Diff-aware con read previo | Idéntico al patrón actual `_publicSubsetFromPartial`: si el partial contiene CUALQUIER trainer field, escribir al public doc. No requiere un read previo (cost extra). Sí escribe cuando alguien hace update con el mismo valor — overhead despreciable, idempotente. Always-write para role==trainer también escribiría cuando se updatean campos no-trainer (bodyWeight, gymId) — gasto inútil. |
| 3 | Trainer fields que disparan dual-write | `displayName, avatarUrl, trainerBio, trainerSpecialty, trainerGeohash, trainerLatitude, trainerLongitude, trainerHourlyRate` | Solo los geo-relevantes | `displayName` y `avatarUrl` ya disparan dual-write a `userPublicProfiles` — al mismo partial agregamos el subset trainer. `trainerBio` se incluye para que la pantalla de profile no requiera segunda lectura (ver Decision #1). |
| 4 | Manejo del caso role==athlete | NO delete del doc `trainerPublicProfiles/{uid}` aunque exista | (a) Cleanup automático cuando role no es trainer; (b) Validación role==trainer antes de dual-write | Role es inmutable (AGENTS.md rule 3). Si el doc existe es porque alguna vez se setearon trainer fields para ese uid — escenario imposible en producción si la regla se respeta. El dual-write se dispara por presencia de partial keys, no por role. Un athlete que jamás escribió trainer fields jamás creará el doc trainerPublicProfiles. Sin lógica de cleanup → menos superficie de bugs. |
| 5 | Geohash5 encoding | Implementación inline pura-Dart en `lib/core/utils/geohash.dart`, ~50 LOC, función pública `String geohash5(double lat, double lon)` | (a) Package `dart_geohash` (200KB+ deps); (b) Package `geocode`; (c) Geohash via `geolocator` extensions | `geolocator ^13.0.0` NO incluye geohash encoding. El algoritmo geohash5 es battle-tested, ~50 LOC, sin dependencias transitivas. Mantiene `lib/core/utils/` libre de packages externos (consistente con `haversine.dart`). Función pura → trivial de testear con vectores conocidos (e.g. lat=-34.6118, lon=-58.4173 → "69y7p" Buenos Aires). |
| 6 | Haversine util | `lib/core/utils/haversine.dart`: `double haversineKm(double lat1, double lon1, double lat2, double lon2)` | Inline en provider | Pura, sin estado, dos consumers (provider + opcionalmente tile display). Misma convención que el resto de utils del core. |
| 7 | Athlete location lifecycle | `StateNotifierProvider<AthleteLocationNotifier, AsyncValue<Position?>>` scoped al feature coach (NOT `.autoDispose`) | (a) Re-fetch en cada mount de TrainersListScreen; (b) Persistir en SharedPreferences | NOT autoDispose: navegar al detalle y volver no debe re-disparar permission dialog. Vive mientras el athlete está dentro del flow coach. Sin persistencia disco: staleness no importa para MVP (las posiciones de trainers son estables; el athlete tampoco se mueve dramáticamente entre sesiones de la app). Permisos: estado `AsyncValue<Position?>` — null = denied/skipped, Position = granted. AsyncLoading = pidiendo permiso. AsyncError = error de hardware (raro). |
| 8 | Permission rationale UX | `showModalBottomSheet` con custom `LocationPermissionRationaleSheet` widget ANTES del system dialog. Solo se muestra si `Geolocator.checkPermission() == LocationPermission.denied`. | (a) `showDialog`; (b) Saltar rationale y ir directo al system dialog | Bottom sheet sigue convención del design system de TREINO (`profile_setup` usa bottom sheets). Skip rationale viola best practice mobile — el usuario es más propenso a aceptar si entiende el por qué. Rationale: "Para encontrar PFs cerca tuyo necesitamos tu ubicación. Sin ella, te mostraremos la lista completa sin orden geográfico." Botones: "Aceptar" → trigger `requestPermission()`. "Ahora no" → state=null, list usa fallback. |
| 9 | List ordering | Repository devuelve trainers SIN ordering deterministic — el provider ordena client-side: (a) si hay location, sort por `haversineKm` ASC; (b) si NO hay location, sort por `displayNameLowercase` ASC. Tiebreaker por `displayName` ASC. | (a) Firestore-side `orderBy displayNameLowercase` siempre; (b) Tiebreaker por `trainerHourlyRate` ASC | El query con geohash prefix usa `isGreaterThanOrEqualTo + isLessThan` (inequality) en `trainerGeohash` — Firestore EXIGE que el primer `orderBy` sea sobre el mismo field. Hacer `.orderBy('trainerGeohash').orderBy('displayNameLowercase')` requeriría un composite index pero la geohash ordering no aporta nada útil (ranking lexicográfico de geohash ≠ ranking por distancia real). Por eso reordeno client-side por haversine. Tiebreaker `displayName` es natural y predecible (no `hourlyRate` que invita debates "el más barato primero" vs "el mejor calificado"). |
| 10 | Specialty filter ubicación | Client-side sobre el result set ya devuelto por el query. Repo expone `specialty` param OPCIONAL pero el provider NO lo pasa | (a) Firestore-side compound query `trainerGeohash + trainerSpecialty`; (b) Specialty obligatorio en repo | Compound query exige composite index `trainerGeohash ASC + trainerSpecialty ASC` que añade complejidad de deploy. Result set por geohash5 es típicamente <50 trainers en zonas urbanas → filtrar in-memory es O(n) trivial. Mantengo el `specialty` opcional en el repo para futuro-proofing (si un día el dataset crece y se justifica el compound index, el contrato del repo ya está listo). **CONFIRMACIÓN: no se agregan composite indexes a `firestore.indexes.json` en PR1.** |
| 11 | Specialty filter UI state | `StateProvider<TrainerSpecialty?>` (null = "Todos") en `trainer_discovery_providers.dart`. UI = single-select chips ("Todos" + 10 specialties). | `StateProvider<Set<TrainerSpecialty>>` (multi-select) | Mockup muestra single-select (chips se ven como pills, no como checkboxes). Multi-select agrega UX complexity sin justificación de mockup. Single-select cubre el caso "atleta busca PF de yoga" — el caso real. |
| 12 | Trainer profile single-read | `trainerByIdProvider(uid)` lee desde `trainerPublicProfiles/{uid}` (NO desde `users/{uid}`) | Read combinado con fallback a `users/{uid}` | `users/{uid}` es owner-only — el atleta no puede leer el doc privado del trainer. `trainerPublicProfiles/{uid}` tiene `read: auth != null` y contiene bio + hourlyRate. Decision #1 asegura que el profile screen renderiza completo con un solo read. |
| 13 | `TrainerSpecialty.fromString()` fallback | Retorna `null` cuando el string no matchea ningún enum value | (a) Categoría sentinel "otros"; (b) Throw | Defensive: si el trainer escribió "Crossfit avanzado" como string en el doc privado, el enum.fromString → null en lugar de explotar el `fromJson`. El profile screen renderiza la categoría como `"–"` cuando es null. No introducir categoría "otros" porque inflaría el enum innecesariamente y no aporta filtering value. |
| 14 | List query limit | `queryByGeohashPrefix` SIN limit (return all matches dentro del prefix). `listAllOrderedByDisplayName(limit: 50)` SÍ con limit | Limit hardcoded en ambos | Geohash5 prefix limita naturalmente a una celda ~5x5km. En zona urbana esperamos <50 trainers — sin limit. En fallback sin location se itera toda la colección, ahí sí hay que limitar (50 es safe para alfa, ajustable). |
| 15 | Empty / Loading / Error states | Mismos patrones que `HistorialSection` (Fase 4 Etapa 4): spinner local con `palette.accent` en loading, `Text(muted) + retry button` en error, copy + opcional CTA en empty | Skeleton loaders | Consistencia visual con el resto de la app. La latencia de Firestore en alfa es <500ms — el spinner cubre. |
| 16 | Distance display formatter | Inline en `TrainerListTile`: `'${distance.toStringAsFixed(1)} km'` para `<10km`, `'${distance.round()} km'` para `≥10km`. Si distance es null → `'—'` | Helper en `lib/core/utils/formatters.dart` | Un solo consumer — inline es justificable. Si Insights u otro feature lo reusa más adelante, extraer entonces. |
| 17 | Router insertion | Sub-route `'trainer/:uid'` bajo el GoRoute `/coach` (dentro del ShellRoute). Ruta resultante: `/coach/trainer/:uid`. Path completo se construye con `context.push('/coach/trainer/${trainer.uid}')` | (a) Top-level fuera de ShellRoute; (b) Bajo `/feed/profile/:uid` | Mantiene bottom bar visible — consistente con `/feed/profile/:uid` que también vive bajo el shell. El profile del trainer es navegable, no immersive. |
| 18 | `AthleteCoachView` modification | Replace stub body con `const TrainersListScreen()` | Render `TrainersListScreen` con padding wrapper | El widget mismo es Scaffold-aware — recibe el SafeArea via el ShellRoute. Sin double-wrap. |
| 19 | `geolocator` version pin | `geolocator: ^13.0.0` (caret) | (a) Exact `13.0.x`; (b) `^12.x` | `^13.0.0` admite minor patches sin breaking changes (semver). Versión más nueva, soporte iOS 17 + Android 14. Probar release builds antes de merge (risk del proposal). |
| 20 | Strict TDD test isolation: dual-write | Test con `fake_cloud_firestore` que assert el batch escribe a AMBOS docs (`users/uid` + `trainerPublicProfiles/uid`) en una sola transacción. Caso negativo: partial sin trainer fields → solo `users/uid` (+ `userPublicProfiles/uid` si aplica) | Integration test contra emulador | `fake_cloud_firestore` ya cubre WriteBatch correctamente (probado en Fase 3 Etapa 5.5). Atomic failure no es trivialmente testeable con fakes — DOC explícito como "deferred a integration test" en spec. |
| 21 | Strict TDD test isolation: Firestore rules | Tests de rules NO se cubren con `fake_cloud_firestore` (no enforce rules). Marcar SCENARIOs específicos como "deferred a integration test contra emulator" y dejar copy en el test file con `markTestSkip(reason: 'emulator required')` | Stub rules en `fake_cloud_firestore` | Mismo patrón usado en `userPublicProfiles` (REQ-UPP-014/015). Los SCENARIOs de rules siguen el formato pero quedan skipped — documentan la intención. |
| 22 | Widget tree composition `TrainersListScreen` | `ConsumerStatefulWidget` con local state mínimo (`bool _rationaleShown` para evitar reshow después de hot reload) | `ConsumerWidget` stateless | Necesita `initState` para disparar el permission flow una sola vez. El permission status real vive en `athleteLocationProvider`. Sin animaciones, sin scroll controllers compartidos. |
| 23 | Widget tree composition `TrainerPublicProfileScreen` | `ConsumerWidget` stateless | `ConsumerStatefulWidget` | Sin estado mutable local — todo state vive en `trainerByIdProvider`. Back nav via `context.canPop() ? pop() : go('/coach')` — mismo patrón que `RoutineDetailScreen`. |
| 24 | Map toggle stub | Render el toggle visualmente (pill: "Mapa" / "Lista") pero el branch "Mapa" muestra `Center(Text('Próximamente'))` | (a) Toggle invisible; (b) Toggle disabled (opacity 0.4) | Mockup parity. Toggle visible = affordance preservada. Tap → estado UI cambia, pero body renderiza placeholder. Mensaje "Próximamente" deja claro que llega. Estado local con `StateProvider<bool> _mapModeProvider` privado al feature. |
| 25 | Iconos nuevos | Añadir `TreinoIcon.specialty` (target/dumbbell), `TreinoIcon.money` ($/wallet), `TreinoIcon.star` (rating placeholder) usando PhosphorIcons como source pero indirectos via `treino_icon.dart` | PhosphorIcons directos | AGENTS.md rule: nunca `PhosphorIcons.X` directamente. Iconos elegidos en apply consultando catálogo Phosphor. |
| 26 | Seeding strategy de trainers de prueba | Script dart en `tool/seed_trainers.dart` (idempotente, escribe 5 trainers seed via Admin SDK) — **DEFERRED a tareas opcionales / docs**. Para apply: documentar manual seeding via Firebase Console como fallback aceptable | Tests dependen del seed | Seeding es out-of-scope del PR pero crítico para validation manual. Lo dejo documentado en tasks como "Optional / DevOps task post-merge". Tests no dependen — usan `fake_cloud_firestore`. |

## File Layout per PR

### PR1 — `feat/coach-discovery-infra` (~250-320 LOC)

**New files**:

| Path | Description |
|------|-------------|
| `lib/features/coach/domain/trainer_public_profile.dart` | Freezed model with 10 fields per Decision #1. |
| `lib/features/coach/domain/trainer_public_profile.freezed.dart` | Generated. |
| `lib/features/coach/domain/trainer_public_profile.g.dart` | Generated JSON serialization. |
| `lib/features/coach/domain/trainer_specialty.dart` | Enum con 10 valores + `fromString` con fallback null (Decision #13). |
| `lib/features/coach/data/trainer_public_profile_repository.dart` | `queryByGeohashPrefix(prefix, {specialty?})` + `listAllOrderedByDisplayName({limit})` + `getByUid(uid)`. |
| `lib/core/utils/haversine.dart` | `double haversineKm(double lat1, double lon1, double lat2, double lon2)`. |
| `lib/core/utils/geohash.dart` | `String geohash5(double lat, double lon)` (inline ~50 LOC). |
| `test/features/coach/domain/trainer_public_profile_test.dart` | Model fromJson/toJson, equality, null handling. SCENARIO-407..409. |
| `test/features/coach/domain/trainer_specialty_test.dart` | `fromString` for all 10 + invalid → null. SCENARIO-410. |
| `test/features/coach/data/trainer_public_profile_repository_test.dart` | Query prefix (returns matches), empty prefix, specialty filter passed through, getByUid found / not-found. SCENARIO-411..413. |
| `test/core/utils/haversine_test.dart` | Conocidos: Buenos Aires↔Rosario ~280km, mismo punto = 0, antípodas ~20015km. SCENARIO-414. |
| `test/core/utils/geohash_test.dart` | Conocidos: BA (-34.6118, -58.4173) → "69y7p", London (51.5, -0.12) → "gcpvj", origen (0,0) → "s0000". Prefix property: dos puntos cercanos comparten prefix. SCENARIO-415. |
| `test/features/profile/data/user_repository_trainer_dual_write_test.dart` | Dual-write batch atomic test usando `fake_cloud_firestore`: partial con trainer fields → both docs updated; partial sin trainer fields → único path. SCENARIO-416..417. |

**Modified files**:

| Path | Change |
|------|--------|
| `lib/features/profile/data/user_repository.dart` | Add `_trainerPublicFields` set + `_trainerPublicSubsetFromPartial(partial)` helper + extend `update()` to add a third `batch.set` when `trainerPublicSubset != null`. Backwards compatible — caller signature unchanged. |
| `firestore.rules` | Add `match /trainerPublicProfiles/{uid}` block mirroring `userPublicProfiles` rules. |
| `pubspec.yaml` | Add `geolocator: ^13.0.0` to dependencies. |
| `ios/Runner/Info.plist` | Add `<key>NSLocationWhenInUseUsageDescription</key><string>Necesitamos tu ubicación para encontrar Personal Trainers cerca tuyo.</string>`. |
| `android/app/src/main/AndroidManifest.xml` | Add `<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>` inside `<manifest>`. |

**NOT modified in PR1**:
- `firestore.indexes.json` — NO compound index needed (Decision #10).
- `lib/features/coach/athlete_coach_view.dart` — stub remains until PR2.
- Any UI file.

### PR2 — `feat/coach-discovery-ui` (~280-350 LOC)

**New files**:

| Path | Description |
|------|-------------|
| `lib/features/coach/presentation/trainers_list_screen.dart` | `TrainersListScreen` ConsumerStatefulWidget. |
| `lib/features/coach/presentation/trainer_public_profile_screen.dart` | `TrainerPublicProfileScreen` ConsumerWidget(required uid). |
| `lib/features/coach/presentation/widgets/trainer_list_tile.dart` | Card del trainer con avatar, displayName, specialty chip, distance, hourlyRate. |
| `lib/features/coach/presentation/widgets/trainer_profile_hero.dart` | Hero con avatar grande + displayName + specialty chip. |
| `lib/features/coach/presentation/widgets/trainer_stats_row.dart` | Row con 3 stats placeholder "–" (RESEÑAS, AÑOS EXP, ALUMNOS). |
| `lib/features/coach/presentation/widgets/trainer_specialty_chips.dart` | Reusable chips (selectable variant para filter, display variant para profile). |
| `lib/features/coach/presentation/widgets/trainer_contact_cta_stub.dart` | Botón "PEDIR VÍNCULO" → SnackBar stub. |
| `lib/features/coach/presentation/widgets/location_permission_rationale_sheet.dart` | Custom bottom sheet content widget. Helper static `show(BuildContext)` returns `Future<bool>` (true = accepted). |
| `lib/features/coach/application/trainer_discovery_providers.dart` | `trainerPublicProfileRepositoryProvider`, `athleteLocationProvider` (StateNotifierProvider), `selectedSpecialtyProvider` (StateProvider), `mapModeProvider` (StateProvider, private feature), `trainerDiscoveryProvider` (FutureProvider.autoDispose), `trainerByIdProvider` (FutureProvider.autoDispose.family). |
| `lib/features/coach/presentation/coach_strings.dart` | Centralized copy: headings, empty/error states, CTA labels, rationale text, specialty display names. |
| `test/features/coach/presentation/trainers_list_screen_test.dart` | Widget tests. SCENARIO-418..423. |
| `test/features/coach/presentation/trainer_public_profile_screen_test.dart` | Widget tests. SCENARIO-424..427. |
| `test/features/coach/application/trainer_discovery_providers_test.dart` | Provider tests: trainerDiscoveryProvider con location → haversine sort; sin location → displayName sort; specialty filter aplica. SCENARIO-428..430. |

**Modified files**:

| Path | Change |
|------|--------|
| `lib/features/coach/athlete_coach_view.dart` | Replace stub body with `const TrainersListScreen()`. |
| `lib/app/router.dart` | Add sub-route `'trainer/:uid'` under existing `GoRoute('/coach')`. Add import for `TrainerPublicProfileScreen`. |
| `lib/core/widgets/treino_icon.dart` | Add `TreinoIcon.specialty`, `TreinoIcon.money`, `TreinoIcon.star` (Decision #25). |

**NOT modified in PR2**:
- Any data layer file (entregado en PR1).
- `firestore.rules` (entregado en PR1).

## Provider Design

    ┌─────────────────────────────────────────────────────────────┐
    │ trainer_discovery_providers.dart                            │
    │                                                             │
    │ trainerPublicProfileRepositoryProvider                      │
    │   Provider<TrainerPublicProfileRepository>                  │
    │   ↓ depends on firestoreProvider                            │
    │                                                             │
    │ athleteLocationProvider                                     │
    │   StateNotifierProvider<AthleteLocationNotifier,            │
    │                          AsyncValue<Position?>>             │
    │   methods: requestIfNeeded(BuildContext)                    │
    │            reset()                                          │
    │   NOT autoDispose (preserves state across detail nav)       │
    │                                                             │
    │ selectedSpecialtyProvider                                   │
    │   StateProvider<TrainerSpecialty?>  (null = "Todos")        │
    │   NOT autoDispose                                           │
    │                                                             │
    │ mapModeProvider  (private to feature, _ prefix)             │
    │   StateProvider<bool>  (false = Lista, true = Mapa-stub)    │
    │                                                             │
    │ trainerDiscoveryProvider                                    │
    │   FutureProvider.autoDispose<List<TrainerPublicProfile>>    │
    │   ↓ ref.watch(athleteLocationProvider)                      │
    │   ↓ ref.watch(selectedSpecialtyProvider)                    │
    │   ↓ ref.watch(trainerPublicProfileRepositoryProvider)       │
    │                                                             │
    │ trainerByIdProvider                                         │
    │   FutureProvider.autoDispose.family                         │
    │     <TrainerPublicProfile?, String /*uid*/>                 │
    │   ↓ ref.watch(trainerPublicProfileRepositoryProvider)       │
    └─────────────────────────────────────────────────────────────┘

### `AthleteLocationNotifier` contract

```dart
class AthleteLocationNotifier extends StateNotifier<AsyncValue<Position?>> {
  AthleteLocationNotifier() : super(const AsyncValue.data(null));

  /// Idempotent. On first call:
  ///   1. Check current permission status.
  ///   2. If denied AND not denied-forever, show rationale sheet, then request.
  ///   3. On grant, fetch position, state = AsyncData(position).
  ///   4. On deny or skip, state = AsyncData(null) (triggers fallback).
  ///   5. On hardware error, state = AsyncError.
  Future<void> requestIfNeeded(BuildContext context) async { ... }

  void reset() => state = const AsyncValue.data(null);
}
```

### Widget test override strategy

```dart
ProviderScope(
  overrides: [
    trainerPublicProfileRepositoryProvider.overrideWithValue(_FakeRepo()),
    athleteLocationProvider.overrideWith((ref) =>
      _FakeLocationNotifier(initial: AsyncValue.data(_buenosAires)),
    ),
    selectedSpecialtyProvider.overrideWith((ref) => null),
    // Or override the high-level discovery provider directly for happy-path tests:
    trainerDiscoveryProvider.overrideWith((ref) async => _fakeTrainers),
    trainerByIdProvider.overrideWith((ref, uid) async => _fakeTrainerById(uid)),
  ],
  child: MaterialApp(home: TrainersListScreen()),
)
```

**Key rule**: tests prefer overriding `trainerDiscoveryProvider` and `trainerByIdProvider` DIRECTLY (Provider-level mocking) over building the chain of repo+location+specialty providers. This isolates UI tests from data layer concerns and is the same pattern as `sessionsByUidProvider` override in `historial_section_test.dart` (Fase 4 Etapa 4 design Decision #2 reuse).

## Widget Tree — `TrainersListScreen`

    TrainersListScreen (ConsumerStatefulWidget)
    └── initState: ref.read(athleteLocationProvider.notifier).requestIfNeeded(context)
    │           (post-frame callback to access BuildContext safely)
    │
    └── build:
        Column
        ├── _Header
        │   └── Row
        │       ├── Text("Entrenadores cerca tuyo", titleLarge)
        │       └── _MapListToggle (pill chip switch, state from mapModeProvider)
        │
        ├── SizedBox(height: 12)
        │
        ├── TrainerSpecialtyChips(mode: filter, selected: ref.watch(selectedSpecialtyProvider))
        │   ─ horizontal scroll: "Todos" + 10 specialty chips
        │   ─ onTap: ref.read(selectedSpecialtyProvider.notifier).state = ...
        │
        ├── SizedBox(height: 16)
        │
        └── Expanded
            └── switch (ref.watch(mapModeProvider)):
                │
                true → Center(Text("Próximamente — vista mapa"))   [stub branch]
                │
                false → switch (ref.watch(trainerDiscoveryProvider)):
                    loading → _ListLoadingState (Center + spinner)
                    error   → _ListErrorState (text + retry button → ref.invalidate)
                    data    → trainers.isEmpty
                                  ? _ListEmptyState (text + reset filter button)
                                  : ListView.builder(
                                      itemCount: trainers.length,
                                      itemBuilder: (_, i) => TrainerListTile(
                                        trainer: trainers[i],
                                        distanceKm: _distanceFor(trainers[i]),
                                        onTap: () => context.push('/coach/trainer/${trainers[i].uid}'),
                                      ),
                                    )

    TrainerListTile (StatelessWidget)
    └── InkWell(onTap)
        └── Container(decoration: card style)
            └── Row(padding: EdgeInsets.all(16))
                ├── PostAvatar(avatarUrl, size: 56)
                ├── SizedBox(width: 12)
                ├── Expanded(Column crossAxis: start
                │     ├── Text(displayName, titleMedium)
                │     ├── SizedBox(height: 4)
                │     ├── Row(specialty chip + " · " + distance text)
                │   )
                ├── Column(crossAxis: end
                │     ├── Text("\$${hourlyRate} / mes" muted)
                │     ├── Row(Icon(star muted) + Text("–"))    ← rating placeholder
                │   )

## Widget Tree — `TrainerPublicProfileScreen`

    TrainerPublicProfileScreen (ConsumerWidget, required uid)
    └── Scaffold(appBar: null)
        └── switch (ref.watch(trainerByIdProvider(uid))):
            │
            loading → _ProfileLoadingState (Center + spinner)
            │
            error   → _ProfileErrorState (column: text + retry)
            │
            data    → trainer == null
                        ? _ProfileNotFound (column: text + back button → context.go('/coach'))
                        : ListView (padding: bottom safe area)
                            ├── _BackBar (IconButton(arrowLeft) onPressed: _onBack)
                            ├── TrainerProfileHero(trainer)
                            ├── SizedBox(height: 20)
                            ├── TrainerStatsRow(stats: [("–", "RESEÑAS"), ("–", "AÑOS EXP"), ("–", "ALUMNOS")])
                            ├── SizedBox(height: 24)
                            ├── if (trainer.trainerBio != null) Padding(child: Text(trainer.trainerBio))
                            ├── if (trainer.trainerSpecialty != null) TrainerSpecialtyChips(mode: display, value: trainer.trainerSpecialty)
                            ├── SizedBox(height: 16)
                            ├── _HourlyRateBlock(value: trainer.trainerHourlyRate)
                            ├── SizedBox(height: 32)
                            └── TrainerContactCtaStub()   ← onTap → SnackBar('Próximamente — Etapa 3')

    _onBack(BuildContext context) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/coach');
      }
    }

## Dual-Write Atomic Strategy (PR1)

### Helper function added to `UserRepository`

```dart
static const _trainerPublicFields = {
  'displayName',          // shared with userPublicProfiles trigger
  'avatarUrl',            // shared with userPublicProfiles trigger
  'trainerBio',
  'trainerSpecialty',
  'trainerGeohash',
  'trainerLatitude',
  'trainerLongitude',
  'trainerHourlyRate',
};

Map<String, Object?>? _trainerPublicSubsetFromPartial(
  Map<String, Object?> partial,
) {
  final hasTrainerField =
      partial.keys.any((k) => _trainerPublicFields.contains(k));
  if (!hasTrainerField) return null;

  final result = <String, Object?>{};
  if (partial.containsKey('displayName')) {
    final name = partial['displayName'] as String?;
    result['displayName'] = name;
    result['displayNameLowercase'] = name?.trim().toLowerCase();
  }
  if (partial.containsKey('avatarUrl')) result['avatarUrl'] = partial['avatarUrl'];
  if (partial.containsKey('trainerBio')) result['trainerBio'] = partial['trainerBio'];
  if (partial.containsKey('trainerSpecialty')) result['trainerSpecialty'] = partial['trainerSpecialty'];
  if (partial.containsKey('trainerGeohash')) result['trainerGeohash'] = partial['trainerGeohash'];
  if (partial.containsKey('trainerLatitude')) result['trainerLatitude'] = partial['trainerLatitude'];
  if (partial.containsKey('trainerLongitude')) result['trainerLongitude'] = partial['trainerLongitude'];
  if (partial.containsKey('trainerHourlyRate')) result['trainerHourlyRate'] = partial['trainerHourlyRate'];
  // uid is required by the rule; always include.
  // It's not in partial but we can read it from outside — better: include uid in the doc id only, NOT in body, OR add 'uid': uid from caller scope. See impl note below.
  return result;
}
```

**Impl note**: el doc id IS `uid`, pero también queremos `uid` en el body (mirrors userPublicProfiles pattern). El `uid` se inyecta en el `update(uid, partial)` scope cuando se ensambla el final map antes del `batch.set`. Tactical concern resuelto en apply — no es decisión arquitectónica.

### Extended `update()` flow

```dart
Future<void> update(String uid, Map<String, Object?> partial) async {
  final sanitized = ... ;  // existing
  final publicSubset = _publicSubsetFromPartial(partial);
  final trainerPublicSubset = _trainerPublicSubsetFromPartial(partial);

  if (publicSubset == null && trainerPublicSubset == null) {
    await _users.doc(uid).set(sanitized, SetOptions(merge: true));
    return;
  }

  final batch = _firestore.batch();
  batch.set(_users.doc(uid), sanitized, SetOptions(merge: true));
  if (publicSubset != null) {
    batch.set(_userPublicProfiles.doc(uid), publicSubset, SetOptions(merge: true));
  }
  if (trainerPublicSubset != null) {
    final body = {'uid': uid, ...trainerPublicSubset};
    batch.set(_trainerPublicProfiles.doc(uid), body, SetOptions(merge: true));
  }
  await batch.commit();
}
```

### Error propagation

`batch.commit()` returns `Future<void>` que throws si la transacción falla. El error se propaga al caller — `UserRepository.update()` mantiene el contrato existente (no swallowing). Tests cubren caso normal (3 paths: only public, only trainer, both). Tests de partial failure deferidos a integration test (fake doesn't enforce atomic semantics fully).

## Firestore Rules Block (PR1)

Insertado en `firestore.rules` después del bloque `userPublicProfiles`:

```javascript
// Trainer public discovery documents — readable by any authenticated user
// for the discovery flow (Fase 5 Etapa 2). Writable only by the owner
// (the trainer themselves). The doc is created/updated via WriteBatch from
// UserRepository.update() when trainer-relevant fields change.
// REQ-COACH-DISC-NNN.
match /trainerPublicProfiles/{uid} {
  allow read: if request.auth != null;

  allow create: if request.auth != null
                && request.auth.uid == uid
                && request.resource.data.uid == uid;

  allow update: if request.auth != null
                && request.auth.uid == uid
                && request.resource.data.uid == resource.data.uid;

  allow delete: if false;
}
```

## Firestore Indexes — NO additions

`firestore.indexes.json` NO se modifica en PR1.

Razón: el query `queryByGeohashPrefix` usa solo inequality sobre `trainerGeohash`. Firestore exige que el primer `orderBy` sea el field de la inequality, pero NO necesitamos ordering server-side (lo hacemos client-side por haversine). Sin orderBy explícito, no hay composite index requirement.

Si en el futuro se quisiera filtrar Firestore-side por `trainerSpecialty` (Decision #10 abre la puerta), entonces sí se agregaría:

```json
{
  "collectionGroup": "trainerPublicProfiles",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "trainerSpecialty", "order": "ASCENDING" },
    { "fieldPath": "trainerGeohash", "order": "ASCENDING" }
  ]
}
```

— pero queda **fuera de scope para esta etapa**. Documentado para futuro reference.

### Deploy step (informativo, no requerido este PR)

Cuando se agregue un compound index en una etapa futura:

```bash
firebase deploy --only firestore:indexes
```

Y se debe coordinar con la propagación de la rule (eventual consistency hasta 10 minutos en Firestore).

## Permission UX Flow

    User opens Coach tab
        │
        ▼
    TrainersListScreen mounts
        │
        ▼
    initState (post-frame callback) → athleteLocationProvider.requestIfNeeded(context)
        │
        ▼
    Geolocator.checkPermission()
        │
        ├── LocationPermission.always | whileInUse
        │     └── fetch position → state = AsyncData(Position)
        │
        ├── LocationPermission.deniedForever
        │     └── state = AsyncData(null)  [no rationale, no system dialog]
        │
        └── LocationPermission.denied (or unable to determine)
              │
              ▼
        show LocationPermissionRationaleSheet
              │
              ├── User taps "Aceptar"
              │     └── Geolocator.requestPermission()
              │           │
              │           ├── granted → fetch position → AsyncData(Position)
              │           └── denied → AsyncData(null)
              │
              └── User dismisses sheet ("Ahora no")
                    └── state = AsyncData(null) [fallback flow]
        │
        ▼
    UI rebuilds:
      state has Position → trainerDiscoveryProvider returns geohash-filtered + haversine-sorted
      state is null → trainerDiscoveryProvider returns full list ordered by displayName

## Risks (Including NEW Ones Found While Designing)

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| (explore) Trainers sin geohash en alfa | High | Seed manual de 3-5 trainers; documented en Decision #26. Fallback en runtime: si query devuelve <3 resultados, podríamos relajar — pero NO se implementa en esta etapa (out-of-scope), solo se documenta. |
| (explore) `geolocator: ^13.0.0` rompe iOS/Android build | Med | Probar release builds antes de merge PR1. Versión cacheada en Decision #19. |
| (explore) PR sizing | Med | Decision-driven split: PR1 ~250-320 LOC, PR2 ~280-350 LOC. Monitorear en apply. |
| (explore) Dual-write race condition | Low | WriteBatch atómico; test cubre los 3 paths felices. Atomic failure deferred a integration. |
| **NEW**: `geohash5` inline impl tiene bug sutil (encoding incorrecto) | Med | Test vectors conocidos: BA, London, origen. Property test (puntos cercanos comparten prefix). Cualquier desviación rompe tests inmediatamente. |
| **NEW**: `Geolocator.requestPermission()` no funciona en simulator/emulator sin mock | High | Para tests: nunca tocar `Geolocator` real — todo el UI test override `athleteLocationProvider` directamente. Para manual QA: documentar configuración del simulator (iOS: Debug > Location > Custom Location). |
| **NEW**: `Position?` `null` ambiguo (denied vs error vs initial vs skipped) | Med | `AsyncValue<Position?>` discrimina: AsyncLoading=requesting, AsyncData(null)=denied/skipped, AsyncData(Position)=granted, AsyncError=hardware error. Documentar en `AthleteLocationNotifier` doc-comment. |
| **NEW**: `trainerDiscoveryProvider` autoDispose se reinicia al volver del detail screen → re-fetch innecesario | Low | Aceptable cost para MVP (single Firestore query). Si en QA se nota lag, considerar `keepAlive: true` o cacheo manual en Etapa siguiente. |
| **NEW**: `TrainerSpecialty.fromString` con strings legacy free-form rompe model fromJson | Low | Decision #13: fallback a null. `fromJson` envuelve con try-catch o usa `TrainerSpecialty.fromString(json['trainerSpecialty'])`. Hot path. |
| **NEW**: `selectedSpecialtyProvider` no autoDispose → filtro persiste entre sesiones de la app | Low | Por diseño (Decision #11). Sí, si el atleta dejó "yoga" seleccionado y vuelve más tarde, lo ve filtrado. UX aceptable. |
| **NEW**: `TrainerProfileHero` requiere `avatarUrl` pero el repo expone `avatarUrl?` (nullable) | Low | Render placeholder avatar (`TreinoIcon.user`) cuando es null. Pattern existente en `PostAvatar`. |
| **NEW**: Bottom sheet rationale aparece DOS veces (initState dispara, user dismiss, rebuild dispara de nuevo) | Med | `_rationaleShown` local bool en `TrainersListScreen` State + check `Geolocator.checkPermission() != denied` antes de show. Solo dispara una vez por mount. |
| **NEW**: `context.canPop()` en `TrainerPublicProfileScreen` cuando se entra por deep-link → fallback a `/coach` puede causar UX raro si athlete jamás visitó coach tab | Low | `context.go('/coach')` es safe — el ShellRoute muestra `AthleteCoachView` (con stub o lista según PR). Sin estado roto. |
| **NEW**: Specialty chips horizontal scroll requiere `SingleChildScrollView` o `ListView.horizontal`. iOS bouncy scroll vs Android edge → no consistente | Low | Usar `SingleChildScrollView(scrollDirection: Axis.horizontal, physics: BouncingScrollPhysics())` para consistencia. Pattern existente en `routine_details_screen.dart` (chips). |
| **NEW**: `fake_cloud_firestore` no soporta `where(isGreaterThanOrEqualTo) + where(isLessThan)` combo en algunos schema edge cases | Low | Verificar en apply — si falla, ajustar al patrón usado en `userPublicProfileRepository.searchByDisplayName` (probado funciona). Mismo combo. |

## Testing Strategy

| Layer | What | Approach | PR |
|-------|------|----------|-----|
| Unit | `geohash5` known vectors (BA, London, origin, prefix property) | `test` group, pure function | PR1 |
| Unit | `haversineKm` known distances (BA↔Rosario, antipodes, same point) | `test` group, pure function | PR1 |
| Unit | `TrainerSpecialty.fromString` (10 valid + invalid → null) | `test` group | PR1 |
| Unit | `TrainerPublicProfile` JSON round-trip | `test` group | PR1 |
| Repo | `queryByGeohashPrefix` returns matches in cell | `fake_cloud_firestore`, seed 5 docs | PR1 |
| Repo | `queryByGeohashPrefix` empty result for unknown prefix | `fake_cloud_firestore` | PR1 |
| Repo | `getByUid` found vs not-found | `fake_cloud_firestore` | PR1 |
| Repo | `listAllOrderedByDisplayName` returns sorted, respects limit | `fake_cloud_firestore` | PR1 |
| Integration | Dual-write batch atomic (3 paths) | `fake_cloud_firestore` UserRepository test | PR1 |
| Integration | `firestore.rules` for trainerPublicProfiles (read auth, write owner) | **SKIPPED with `markTestSkip` — deferred to emulator** | PR1 |
| Widget | `TrainersListScreen`: loading, error, empty, with-trainers states | `ProviderScope` with `trainerDiscoveryProvider` override | PR2 |
| Widget | `TrainersListScreen`: specialty chip tap updates filter | override `selectedSpecialtyProvider` + assert UI change | PR2 |
| Widget | `TrainersListScreen`: map toggle → renders "Próximamente" | override `mapModeProvider` | PR2 |
| Widget | `TrainersListScreen`: tap tile navigates to `/coach/trainer/:uid` | wrap in router with overrides | PR2 |
| Widget | `TrainersListScreen`: permission rationale sheet shows on first mount | mock permission status + verify `find.byType(LocationPermissionRationaleSheet)` | PR2 |
| Widget | `TrainerPublicProfileScreen`: loading, error, not-found, loaded states | override `trainerByIdProvider` | PR2 |
| Widget | `TrainerPublicProfileScreen`: CTA stub shows SnackBar | tap, verify `find.text('Próximamente — Etapa 3')` | PR2 |
| Widget | `TrainerPublicProfileScreen`: back nav from stack vs deep-link | router push vs initial location | PR2 |
| Provider | `trainerDiscoveryProvider`: with location → sorted by haversine | container with overrides | PR2 |
| Provider | `trainerDiscoveryProvider`: without location → sorted by displayName | container with overrides | PR2 |
| Provider | `trainerDiscoveryProvider`: specialty filter excludes non-matching | container with overrides | PR2 |
| Router | `/coach/trainer/:uid` resolves to `TrainerPublicProfileScreen` | router test | PR2 |
| Router | `/coach/trainer/:uid` keeps bottom bar visible (sub-route under ShellRoute) | assert `find.byType(TreinoBottomBar)` | PR2 |

Total: ~24 SCENARIOs split ~11/PR1 + ~13/PR2 (consistent with proposal SCENARIO range 407..~430).

## Strict TDD Plan

Tests RED FIRST, then implementation GREEN. Order matters.

### PR1 — RED → GREEN order

1. **RED**: `geohash_test.dart` — write tests for `geohash5` (known vectors + prefix property).
2. **GREEN**: implement `lib/core/utils/geohash.dart`.
3. **RED**: `haversine_test.dart` — write tests for `haversineKm`.
4. **GREEN**: implement `lib/core/utils/haversine.dart`.
5. **RED**: `trainer_specialty_test.dart` — write tests for enum + `fromString`.
6. **GREEN**: implement `trainer_specialty.dart`.
7. **RED**: `trainer_public_profile_test.dart` — write JSON round-trip tests.
8. **GREEN**: implement `trainer_public_profile.dart` + run `build_runner` for freezed/g.
9. **RED**: `trainer_public_profile_repository_test.dart` — query + getById tests with fake.
10. **GREEN**: implement `trainer_public_profile_repository.dart`.
11. **RED**: `user_repository_trainer_dual_write_test.dart` — assert batch writes to all relevant docs.
12. **GREEN**: extend `user_repository.dart` with `_trainerPublicFields` + `_trainerPublicSubsetFromPartial` + modify `update()`.
13. Modify `firestore.rules`, `pubspec.yaml`, `Info.plist`, `AndroidManifest.xml` (no tests, infra-only).
14. Gate: `flutter analyze` 0 issues + `dart format .` + `flutter test` green + `flutter build ios --release` smoke + `flutter build apk --release` smoke (manual).

### PR2 — RED → GREEN order (assumes PR1 merged & rebased)

15. **RED**: `trainer_discovery_providers_test.dart` — provider tests with overrides.
16. **GREEN**: implement `trainer_discovery_providers.dart`.
17. **RED**: `trainer_public_profile_screen_test.dart` — widget tests.
18. **GREEN**: implement `trainer_public_profile_screen.dart` + dependent widgets (hero, stats row, specialty chips, CTA stub).
19. **RED**: `trainers_list_screen_test.dart` — widget tests.
20. **GREEN**: implement `trainers_list_screen.dart` + `trainer_list_tile.dart` + `location_permission_rationale_sheet.dart`.
21. **RED**: router test for `/coach/trainer/:uid`.
22. **GREEN**: add sub-route to `router.dart`.
23. **RED**: existing `coach_screen_test.dart` (if any) updated to expect `TrainersListScreen` instead of stub copy.
24. **GREEN**: modify `athlete_coach_view.dart` to render `TrainersListScreen`.
25. **GREEN**: add icons to `treino_icon.dart` (after grep confirms current catalogue).
26. Gate: `flutter analyze` 0 issues + `dart format .` + `flutter test` green.

Strict TDD means no production code is written before its corresponding test is red. The order above guarantees that property.

## Open Questions

None blocking — todas las open questions del proposal resueltas en este design:

- **Q1 (seeding script)**: Decision #26 — documented as optional post-merge DevOps task; not in PR scope.
- **Q2 (formatting helper)**: Decision #16 — inline en TrainerListTile; extract later if reused.
- **Q3 (`TrainerSpecialty.fromString` fallback)**: Decision #13 — `null` (no sentinel "otros").
- **Q4 (permission rationale UX)**: Decision #8 — `showModalBottomSheet` + custom widget.
- **Q5 (ordering tiebreaker)**: Decision #9 — `displayName ASC` tiebreaker.
- **Q6 (PR2 further split)**: NOT needed per estimated ~280-350 LOC. Monitor en apply; if it exceeds 380 LOC, consider widgets-then-screens split — but explicit decision is "stay as one PR2 unless threshold exceeded".

## Review Workload Forecast

- **400-line budget risk**: High en una sola unidad — RESUELTO con chained PRs.
- **Chained PRs recommended**: Yes (PR1 infra + PR2 UI).
- **Decision needed before apply**: No — el split y los boundaries quedan locked en este design.
- **Estimated changed lines**: PR1 ~250-320 / PR2 ~280-350 / total ~530-670.
- **Delivery strategy**: chained PRs (already cached at orchestrator level).
