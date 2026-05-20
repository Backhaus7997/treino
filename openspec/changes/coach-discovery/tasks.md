# Tasks: Coach Discovery (Fase 5 · Etapa 2)

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines — PR1 | ~250-320 |
| Estimated changed lines — PR2 | ~280-350 |
| Estimated changed lines — total | ~530-670 |
| 400-line budget risk — PR1 | Low (within budget) |
| 400-line budget risk — PR2 | Low (within budget) |
| 400-line budget risk — single PR | High |
| Chained PRs recommended | Yes |
| Suggested split | PR1 (`feat/coach-discovery-infra`) → PR2 (`feat/coach-discovery-ui`) |
| Delivery strategy | auto-chain |
| Chain strategy | feature-branch-chain |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Branch | Base | Likely PR | Notes |
|------|------|--------|------|-----------|-------|
| PR1 | Infra: model + repo + utils + dual-write + platform config | `feat/coach-discovery-infra` | `main` | PR 1 | Self-contained; UI stub unchanged; fully mergeable standalone |
| PR2 | UI: screens + widgets + providers + router sub-route | `feat/coach-discovery-ui` | `feat/coach-discovery-infra` | PR 2 | Depends on PR1 merge; rebase onto main after PR1 merges |

---

## PR1: Coach Discovery Infra — branch `feat/coach-discovery-infra`

### T01 [1] [CHORE] Branch + directories

- **Files**: none (git/filesystem only)
- **Description**: Checkout `feat/coach-discovery-infra` from `main`. Create directories `lib/features/coach/domain/`, `lib/features/coach/data/`, `lib/core/utils/` (if absent), and corresponding `test/` mirrors.
- **Acceptance**: `git branch` shows `feat/coach-discovery-infra`; `flutter test` baseline green.

---

### T02 [1] [CHORE] pubspec.yaml — add geolocator dependency

- **Files**: `pubspec.yaml` (MODIFIED)
- **Description**: Add `geolocator: ^13.0.0` under `dependencies`. Run `flutter pub get` to confirm resolution.
- **Acceptance**: `pubspec.lock` contains `geolocator 13.x.x`; `flutter pub get` exits 0.

---

### T03 [1] [CHORE] iOS Info.plist — location usage description

- **Files**: `ios/Runner/Info.plist` (MODIFIED)
- **Description**: Add `<key>NSLocationWhenInUseUsageDescription</key><string>Necesitamos tu ubicación para encontrar Personal Trainers cerca tuyo.</string>` inside the root `<dict>`.
- **Acceptance**: Key present in file; `flutter build ios --release` (manual smoke, not CI) compiles without location permission warnings.

---

### T04 [1] [CHORE] Android AndroidManifest — ACCESS_FINE_LOCATION permission

- **Files**: `android/app/src/main/AndroidManifest.xml` (MODIFIED)
- **Description**: Add `<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>` inside the `<manifest>` element (before `<application>`).
- **Acceptance**: Key present in file; `flutter build apk --release` (manual smoke) compiles without permission errors.

---

### T05 [1] [RED] Unit tests — `geohash5`

- **Files**: `test/core/utils/geohash_test.dart` (NEW)
- **SCENARIOs**: SCENARIO-422
- **REQs**: REQ-COACH-DISC-DATA-011
- **Description**: Write failing tests: (1) `geohash5(-34.6037, -58.3816)` returns a 5-char String starting with `'p0q'` (Buenos Aires — SCENARIO-422); (2) result length == 5 for any valid lat/lon; (3) all result chars belong to base32 geohash alphabet (`0-9, b-h, j-n, p-z`); (4) two points <1km apart share the same 5-char prefix (property test with fixed pair). `geohash5` is undefined → tests fail with `Error`.
- **Acceptance**: `flutter test test/core/utils/geohash_test.dart` exits non-zero; 4 test cases declared.

---

### T06 [1] [GREEN] Implement `lib/core/utils/geohash.dart`

- **Files**: `lib/core/utils/geohash.dart` (NEW)
- **REQs**: REQ-COACH-DISC-DATA-011
- **Description**: Implement top-level `String geohash5(double lat, double lon)` (~50 LOC). Standard base32 alphabet `'0123456789bcdefghjkmnpqrstuvwxyz'`. Pure function, no side effects, no imports. Returns first 5 chars of the standard geohash encoding.
- **Acceptance**: `flutter test test/core/utils/geohash_test.dart` all green.

---

### T07 [1] [RED] Unit tests — `haversineKm`

- **Files**: `test/core/utils/haversine_test.dart` (NEW)
- **SCENARIOs**: SCENARIO-420, SCENARIO-421
- **REQs**: REQ-COACH-DISC-DATA-010
- **Description**: Write failing tests: (1) Buenos Aires → Santiago de Chile is between 1140.0 and 1160.0 km (SCENARIO-420); (2) identical coordinates return `0.0` (SCENARIO-421); (3) result is symmetric (`haversineKm(a,b,c,d) == haversineKm(c,d,a,b)`). `haversineKm` is undefined → tests fail.
- **Acceptance**: `flutter test test/core/utils/haversine_test.dart` exits non-zero; 3 test cases declared.

---

### T08 [1] [GREEN] Implement `lib/core/utils/haversine.dart`

- **Files**: `lib/core/utils/haversine.dart` (NEW)
- **REQs**: REQ-COACH-DISC-DATA-010
- **Description**: Implement top-level `double haversineKm(double lat1, double lon1, double lat2, double lon2)` with Earth radius = 6371.0 km. Pure function. No class wrapping.
- **Acceptance**: `flutter test test/core/utils/haversine_test.dart` all green.

---

### T09 [1] [RED] Unit tests — `TrainerSpecialty` enum

- **Files**: `test/features/coach/domain/trainer_specialty_test.dart` (NEW)
- **SCENARIOs**: SCENARIO-409, SCENARIO-410
- **REQs**: REQ-COACH-DISC-DATA-003
- **Description**: Write failing tests: (1) `TrainerSpecialty.values.length == 10` (SCENARIO-409); (2) values list contains exactly `powerlifting, crossfit, bodybuilding, hipertrofia, wellness, kinesiologia, funcional, running, yoga, calistenia`; (3) `TrainerSpecialty.fromString('Hipertrofia')` returns `TrainerSpecialty.hipertrofia` (case-insensitive — SCENARIO-410); (4) `TrainerSpecialty.fromString('spinning')` returns `null` without throwing; (5) all 10 values roundtrip through `fromString(value.name)`.
- **Acceptance**: `flutter test test/.../trainer_specialty_test.dart` exits non-zero; 5 test cases declared.

---

### T10 [1] [GREEN] Implement `lib/features/coach/domain/trainer_specialty.dart`

- **Files**: `lib/features/coach/domain/trainer_specialty.dart` (NEW)
- **REQs**: REQ-COACH-DISC-DATA-003
- **Description**: Define `enum TrainerSpecialty` with 10 values in spec order. Add static `TrainerSpecialty? fromString(String value)` factory performing case-insensitive match; returns `null` for unknown input (D13).
- **Acceptance**: `flutter test test/.../trainer_specialty_test.dart` all green.

---

### T11 [1] [RED] Unit tests — `TrainerPublicProfile` model

- **Files**: `test/features/coach/domain/trainer_public_profile_test.dart` (NEW)
- **SCENARIOs**: SCENARIO-407, SCENARIO-408
- **REQs**: REQ-COACH-DISC-DATA-001, REQ-COACH-DISC-DATA-002
- **Description**: Write failing tests: (1) full-fields JSON roundtrip (SCENARIO-407): construct with all 10 fields, `toJson()` → `fromJson()`, assert equality; (2) nullable-null roundtrip (SCENARIO-408): construct with only `uid`, `displayName`, `displayNameLowercase`, assert all nullable fields are null after roundtrip; (3) `displayNameLowercase` equals `displayName.toLowerCase()` invariant check. `TrainerPublicProfile` is undefined → tests fail.
- **Acceptance**: `flutter test test/.../trainer_public_profile_test.dart` exits non-zero; 3 test cases declared.

---

### T12 [1] [GREEN] Implement `TrainerPublicProfile` freezed model + generated files

- **Files**: `lib/features/coach/domain/trainer_public_profile.dart` (NEW), `lib/features/coach/domain/trainer_public_profile.freezed.dart` (GENERATED), `lib/features/coach/domain/trainer_public_profile.g.dart` (GENERATED)
- **REQs**: REQ-COACH-DISC-DATA-001, REQ-COACH-DISC-DATA-002
- **Description**: Define `@freezed TrainerPublicProfile` with fields: `uid`, `displayName`, `displayNameLowercase` (non-nullable) and `avatarUrl?, trainerBio?, trainerSpecialty?, trainerGeohash?, trainerLatitude?, trainerLongitude?, trainerHourlyRate?` (nullable). Add `@JsonSerializable()` annotations. Run `flutter pub run build_runner build --delete-conflicting-outputs` to generate `.freezed.dart` and `.g.dart`.
- **Acceptance**: `flutter test test/.../trainer_public_profile_test.dart` all green; generated files committed.

---

### T13 [1] [RED] Repo tests — `TrainerPublicProfileRepository`

- **Files**: `test/features/coach/data/trainer_public_profile_repository_test.dart` (NEW)
- **SCENARIOs**: SCENARIO-411, SCENARIO-412, SCENARIO-413, SCENARIO-414, SCENARIO-415
- **REQs**: REQ-COACH-DISC-DATA-004, REQ-COACH-DISC-DATA-005, REQ-COACH-DISC-DATA-006, REQ-COACH-DISC-DATA-007
- **Description**: Using `fake_cloud_firestore`. Write failing tests: (1) `listByGeohashPrefix('p0qh')` returns trainer A (`geohash: 'p0qh2'`) and B (`'p0qh3'`) but NOT C (`'xyz99'`) — SCENARIO-411; (2) `listByGeohashPrefix('p0qh', specialty: TrainerSpecialty.yoga)` returns only yoga trainer — SCENARIO-412; (3) `listByGeohashPrefix('p0qh')` on collection with only `'xyz'` geohashes returns empty list — SCENARIO-413; (4) `listAll()` returns all trainers ordered by `displayName` ascending — SCENARIO-414; (5) `getById('nonexistent')` returns `null` without throwing — SCENARIO-415. Repository is undefined → tests fail.
- **Acceptance**: `flutter test test/.../trainer_public_profile_repository_test.dart` exits non-zero; 5 test cases declared.

---

### T14 [1] [GREEN] Implement `lib/features/coach/data/trainer_public_profile_repository.dart`

- **Files**: `lib/features/coach/data/trainer_public_profile_repository.dart` (NEW)
- **REQs**: REQ-COACH-DISC-DATA-004..007
- **Description**: Implement `TrainerPublicProfileRepository` with: `listByGeohashPrefix(String prefix5, {TrainerSpecialty? specialty})` using `isGreaterThanOrEqualTo: prefix5, isLessThan: prefix5 + ''`, client-side specialty filter; `listAll({TrainerSpecialty? specialty, int limit = 50})` ordered by `displayNameLowercase` ASC with client-side specialty filter; `getById(String uid)` returning null on missing doc. Uses `FirebaseFirestore` injection via constructor.
- **Acceptance**: `flutter test test/.../trainer_public_profile_repository_test.dart` all green.

---

### T15 [1] [RED] Integration tests — `UserRepository` dual-write

- **Files**: `test/features/profile/data/user_repository_trainer_dual_write_test.dart` (NEW)
- **SCENARIOs**: SCENARIO-423, SCENARIO-424
- **REQs**: REQ-COACH-DISC-DUAL-001, REQ-COACH-DISC-DUAL-002
- **Description**: Using `fake_cloud_firestore`. Write failing tests: (1) `update('trainer-1', {'trainerSpecialty': 'yoga', 'trainerLatitude': -34.6})` writes to both `users/trainer-1` AND `trainerPublicProfiles/trainer-1` — SCENARIO-423; (2) `update('athlete-1', {'gymId': 'gym-42'})` writes to `users/athlete-1` but `trainerPublicProfiles/athlete-1` does NOT exist — SCENARIO-424; (3) `update(uid, {'displayName': 'Ana'})` writes to `users/uid`, `userPublicProfiles/uid`, AND `trainerPublicProfiles/uid` (trainer field triggers all three). `_trainerPublicSubsetFromPartial` is undefined → tests fail.
- **Acceptance**: `flutter test test/.../user_repository_trainer_dual_write_test.dart` exits non-zero; 3 test cases declared.

---

### T16 [1] [GREEN] Extend `lib/features/profile/data/user_repository.dart` — dual-write

- **Files**: `lib/features/profile/data/user_repository.dart` (MODIFIED)
- **REQs**: REQ-COACH-DISC-DUAL-001, REQ-COACH-DISC-DUAL-002
- **Description**: Add `static const _trainerPublicFields = {'displayName', 'avatarUrl', 'trainerBio', 'trainerSpecialty', 'trainerGeohash', 'trainerLatitude', 'trainerLongitude', 'trainerHourlyRate'}`. Add `Map<String, Object?>? _trainerPublicSubsetFromPartial(Map<String, Object?> partial)` — returns null if no trainer field present; otherwise builds subset map including `displayNameLowercase` derived from `displayName`. Extend `update()`: if either `publicSubset` or `trainerPublicSubset` is non-null, use `WriteBatch` with up to 3 sets (`users/uid` always, `userPublicProfiles/uid` if publicSubset, `trainerPublicProfiles/uid` if trainerPublicSubset — injects `'uid': uid` into trainerPublicSubset body). Caller signature unchanged.
- **Acceptance**: `flutter test test/.../user_repository_trainer_dual_write_test.dart` all green; existing `user_repository` tests remain green.

---

### T17 [1] [MOD] `firestore.rules` — add `trainerPublicProfiles` block

- **Files**: `firestore.rules` (MODIFIED)
- **SCENARIOs**: SCENARIO-416, SCENARIO-417, SCENARIO-418, SCENARIO-419 (deferred to emulator — see note)
- **REQs**: REQ-COACH-DISC-DATA-008, REQ-COACH-DISC-DATA-009
- **Description**: Insert the `match /trainerPublicProfiles/{uid}` block after the `userPublicProfiles` block: `allow read: if request.auth != null;` `allow create: if request.auth != null && request.auth.uid == uid && request.resource.data.uid == uid;` `allow update: if request.auth != null && request.auth.uid == uid && request.resource.data.uid == resource.data.uid;` `allow delete: if false;`. SCENARIO-416..419 tests are created as `markTestSkip(reason: 'emulator required')` stubs in `test/features/coach/data/firestore_rules_test.dart` (NEW, skipped) per D21.
- **Acceptance**: Rules block present in file; stub test file compiles and all tests are skipped (not failing).

---

### T18 [1] [QA] PR1 quality gate

- **Files**: none (command-only)
- **Description**: Run `flutter analyze` (0 issues required), then `dart format .` (no unformatted files), then `flutter test` (full suite green including all new PR1 tests). BLOCKER — do not open PR1 until all three pass.
- **Acceptance**: All three commands exit 0.

---

## PR2: Coach Discovery UI — branch `feat/coach-discovery-ui`

> PR2 tasks MUST NOT begin until PR1 is merged into `main` and `feat/coach-discovery-ui` is branched from `feat/coach-discovery-infra` (or rebased onto the merged `main`).

---

### T19 [2] [CHORE] Branch from merged PR1

- **Files**: none
- **Description**: After PR1 merges to `main`: checkout `main`, pull, create `feat/coach-discovery-ui` from `main`. Confirm `flutter test` baseline green (PR1 tests pass). Create directories `lib/features/coach/presentation/widgets/`, `lib/features/coach/application/`, and corresponding `test/` mirrors.
- **Acceptance**: `git log --oneline -1` shows PR1 merge commit; `flutter test` green.

---

### T20 [2] [CHORE] `lib/features/coach/presentation/coach_strings.dart` — create CoachStrings

- **Files**: `lib/features/coach/presentation/coach_strings.dart` (NEW)
- **Description**: Define `abstract final class CoachStrings` with string constants: `trainersListTitle` (`'Entrenadores cerca tuyo'`), `trainersListEmpty` (`'No hay entrenadores en tu zona'`), `trainersListError` (`'Error al cargar entrenadores'`), `trainersListRetry` (`'Reintentar'`), `mapToggleLabel` (`'MAPA'`), `mapComingSoon` (`'Próximamente — vista mapa'`), `filterAll` (`'Todos'`), `profileNotFound` (`'Perfil no encontrado'`), `profileNotFoundBack` (`'Volver'`), `profileError` (`'Error al cargar el perfil'`), `ctaLabel` (`'PEDIR VÍNCULO'`), `ctaSnackBar` (`'Próximamente — Etapa 3'`), `rationaleTitle`, `rationaleBody`, `rationaleAccept` (`'Aceptar'`), `rationaleDismiss` (`'Ahora no'`), `statsResenas` (`'RESEÑAS'`), `statsYearsExp` (`'AÑOS EXP'`), `statsStudents` (`'ALUMNOS'`), `statsPlaceholder` (`'–'`), plus a `Map<TrainerSpecialty, String> specialtyLabels` with display names for all 10 specialties.
- **Acceptance**: File compiles; `flutter analyze` 0 issues on this file.

---

### T21 [2] [CHORE] `lib/core/widgets/treino_icon.dart` — add new icons

- **Files**: `lib/core/widgets/treino_icon.dart` (MODIFIED)
- **Description**: Add `TreinoIcon.specialty`, `TreinoIcon.money`, `TreinoIcon.star` constants using appropriate `PhosphorIcons` source values (consult Phosphor catalogue during apply). Follow existing convention in the file — never expose `PhosphorIcons.X` directly.
- **Acceptance**: `TreinoIcon.specialty`, `TreinoIcon.money`, `TreinoIcon.star` resolve without import; `flutter analyze` 0 issues.

---

### T22 [2] [RED] Provider tests — `AthleteLocationNotifier` permission flow states

- **Files**: `test/features/coach/application/trainer_discovery_providers_test.dart` (NEW)
- **REQs**: REQ-COACH-DISC-UI-011
- **Description**: Write failing tests for `AthleteLocationNotifier`: (1) initial state is `AsyncData(null)`; (2) after `requestIfNeeded` with mocked `granted` permission → state becomes `AsyncData(Position)`; (3) after `requestIfNeeded` with mocked `denied` → state stays `AsyncData(null)`; (4) after `requestIfNeeded` with mocked hardware error → state becomes `AsyncError`. Provider and notifier are undefined → tests fail.
- **Acceptance**: `flutter test test/.../trainer_discovery_providers_test.dart` exits non-zero; 4 test cases declared.

---

### T23 [2] [GREEN] Implement `AthleteLocationNotifier` in `trainer_discovery_providers.dart`

- **Files**: `lib/features/coach/application/trainer_discovery_providers.dart` (NEW, partial)
- **REQs**: REQ-COACH-DISC-UI-011
- **Description**: Implement `AthleteLocationNotifier extends StateNotifier<AsyncValue<Position?>>` with `requestIfNeeded(BuildContext context)`. Logic: check permission status; if `deniedForever` → `AsyncData(null)`; if `denied` → show `LocationPermissionRationaleSheet` → on accept request permission → on grant fetch position → `AsyncData(position)`, on deny → `AsyncData(null)`; on hardware error → `AsyncError`. Define `athleteLocationProvider = StateNotifierProvider<AthleteLocationNotifier, AsyncValue<Position?>>`. NOT autoDispose (D7).
- **Acceptance**: `flutter test test/.../trainer_discovery_providers_test.dart` 4 green.

---

### T24 [2] [RED] Provider tests — `trainerDiscoveryProvider` (with/without location, specialty filter)

- **Files**: `test/features/coach/application/trainer_discovery_providers_test.dart` (MODIFIED)
- **REQs**: REQ-COACH-DISC-UI-002..005, REQ-COACH-DISC-UI-008, REQ-COACH-DISC-UI-011
- **Description**: Add failing tests: (1) with `AsyncData(position)` in `athleteLocationProvider` → provider calls `listByGeohashPrefix` and result is sorted by haversine ASC; (2) with `AsyncData(null)` → provider calls `listAll` and result is ordered by `displayName`; (3) with `selectedSpecialtyProvider = TrainerSpecialty.yoga` → only yoga trainers in result; (4) `trainerDiscoveryProvider` is `FutureProvider.autoDispose`. Provider not fully implemented → tests fail.
- **Acceptance**: New test cases exit non-zero.

---

### T25 [2] [GREEN] Implement `trainerDiscoveryProvider` and `trainerByIdProvider`

- **Files**: `lib/features/coach/application/trainer_discovery_providers.dart` (MODIFIED)
- **REQs**: REQ-COACH-DISC-UI-001..011
- **Description**: Add to the providers file: `trainerPublicProfileRepositoryProvider = Provider<TrainerPublicProfileRepository>` (depends on `firestoreProvider`); `selectedSpecialtyProvider = StateProvider<TrainerSpecialty?>` (null = Todos, NOT autoDispose); `mapModeProvider = StateProvider<bool>` (private, _ prefix); `trainerDiscoveryProvider = FutureProvider.autoDispose<List<TrainerPublicProfile>>` watching `athleteLocationProvider`, `selectedSpecialtyProvider`, `trainerPublicProfileRepositoryProvider` — calls `listByGeohashPrefix` when location is non-null (with `geohash5`) then haversine-sorts, else calls `listAll`, then applies client-side specialty filter; `trainerByIdProvider = FutureProvider.autoDispose.family<TrainerPublicProfile?, String>` calling `repo.getById(uid)`.
- **Acceptance**: All provider tests green.

---

### T26 [2] [RED] Widget tests — `TrainerListTile`

- **Files**: `test/features/coach/presentation/widgets/trainer_list_tile_test.dart` (NEW)
- **SCENARIOs**: SCENARIO-429
- **REQs**: REQ-COACH-DISC-UI-006
- **Description**: Write failing tests: (1) tile renders `displayName` text; (2) specialty chip shows `'yoga'` label when `trainerSpecialty = TrainerSpecialty.yoga` — SCENARIO-429; (3) distance `'3.2'` visible when `distanceKm: 3.2`; (4) rate `'5000'` visible when `trainerHourlyRate: 5000`; (5) distance shows `'—'` when `distanceKm` is null; (6) `PostAvatar` widget is in the tree; (7) no star rating widget present. Widget undefined → tests fail.
- **Acceptance**: `flutter test test/.../trainer_list_tile_test.dart` exits non-zero; 7 test cases declared.

---

### T27 [2] [GREEN] Implement `lib/features/coach/presentation/widgets/trainer_list_tile.dart`

- **Files**: `lib/features/coach/presentation/widgets/trainer_list_tile.dart` (NEW)
- **REQs**: REQ-COACH-DISC-UI-006
- **Description**: Implement `TrainerListTile extends StatelessWidget` with `required TrainerPublicProfile trainer`, `double? distanceKm`, `required VoidCallback onTap`. Renders: `PostAvatar(avatarUrl, size: 56)`, `displayName`, specialty chip (from `CoachStrings.specialtyLabels` or omitted if null), distance formatted inline per D16 (`toStringAsFixed(1) km` < 10km, `round() km` ≥ 10km, `'—'` if null), hourly rate `'$rate / hr'` or omitted. Wrapped in `InkWell(onTap)`.
- **Acceptance**: `flutter test test/.../trainer_list_tile_test.dart` all green.

---

### T28 [2] [RED] Widget tests — `TrainerSpecialtyChips`

- **SCENARIOs**: SCENARIO-430, SCENARIO-431
- **Files**: `test/features/coach/presentation/widgets/trainer_specialty_chips_test.dart` (NEW)
- **REQs**: REQ-COACH-DISC-UI-007, REQ-COACH-DISC-UI-008
- **Description**: Write failing tests: (1) chip row contains exactly 11 chips (10 + "Todos") — SCENARIO-430; (2) "Todos" chip is selected by default; (3) `onSelected(TrainerSpecialty.yoga)` fires when yoga chip tapped; (4) `onSelected(null)` fires when "Todos" tapped; (5) only one chip is selected at a time.
- **Acceptance**: `flutter test test/.../trainer_specialty_chips_test.dart` exits non-zero; 5 test cases declared.

---

### T29 [2] [GREEN] Implement `lib/features/coach/presentation/widgets/trainer_specialty_chips.dart`

- **Files**: `lib/features/coach/presentation/widgets/trainer_specialty_chips.dart` (NEW)
- **REQs**: REQ-COACH-DISC-UI-007, REQ-COACH-DISC-UI-008
- **Description**: Implement `TrainerSpecialtyChips extends StatelessWidget` with `TrainerSpecialty? selected`, `required ValueChanged<TrainerSpecialty?> onSelected`. Renders `SingleChildScrollView(scrollDirection: Axis.horizontal, physics: BouncingScrollPhysics())` containing "Todos" chip + 10 specialty chips using `CoachStrings.specialtyLabels`. Single-select: only the chip matching `selected` is in selected state.
- **Acceptance**: `flutter test test/.../trainer_specialty_chips_test.dart` all green.

---

### T30 [2] [RED] Widget tests — `TrainerProfileHero`, `TrainerStatsRow`, `TrainerContactCtaStub`

- **Files**: `test/features/coach/presentation/widgets/trainer_profile_widgets_test.dart` (NEW)
- **REQs**: REQ-COACH-DISC-UI-015, REQ-COACH-DISC-UI-016
- **Description**: Write failing tests: (1) `TrainerProfileHero` renders `displayName` and specialty chip; (2) `TrainerProfileHero` renders `PostAvatar`; (3) `TrainerStatsRow` renders 3 stat tiles with labels `'RESEÑAS'`, `'AÑOS EXP'`, `'ALUMNOS'` and value `'–'` each; (4) `TrainerContactCtaStub` renders button with text `'PEDIR VÍNCULO'`; (5) tap on `TrainerContactCtaStub` calls `onTap` callback. Widgets undefined → tests fail.
- **Acceptance**: `flutter test test/.../trainer_profile_widgets_test.dart` exits non-zero; 5 test cases declared.

---

### T31 [2] [GREEN] Implement `TrainerProfileHero`, `TrainerStatsRow`, `TrainerContactCtaStub`

- **Files**: `lib/features/coach/presentation/widgets/trainer_profile_hero.dart` (NEW), `lib/features/coach/presentation/widgets/trainer_stats_row.dart` (NEW), `lib/features/coach/presentation/widgets/trainer_contact_cta_stub.dart` (NEW)
- **REQs**: REQ-COACH-DISC-UI-015, REQ-COACH-DISC-UI-016
- **Description**: `TrainerProfileHero`: full-bleed area with `PostAvatar` (large), `displayName`, specialty chip. New widget — do NOT reuse `PublicProfileHero`. `TrainerStatsRow`: row with exactly 3 stat tiles (RESEÑAS/AÑOS EXP/ALUMNOS) all showing `CoachStrings.statsPlaceholder` (`'–'`). `TrainerContactCtaStub`: `ElevatedButton` with label `CoachStrings.ctaLabel`; `onTap` callback exposed.
- **Acceptance**: `flutter test test/.../trainer_profile_widgets_test.dart` all green.

---

### T32 [2] [RED] Widget test — `LocationPermissionRationaleSheet`

- **Files**: `test/features/coach/presentation/widgets/location_permission_rationale_sheet_test.dart` (NEW)
- **REQs**: REQ-COACH-DISC-UI-011
- **Description**: Write failing tests: (1) sheet renders rationale body text from `CoachStrings.rationaleBody`; (2) "Aceptar" button is present; (3) "Ahora no" button is present; (4) tapping "Aceptar" triggers the `onAccepted` callback; (5) tapping "Ahora no" triggers the `onDismissed` callback. Widget undefined → tests fail.
- **Acceptance**: `flutter test test/.../location_permission_rationale_sheet_test.dart` exits non-zero; 5 test cases declared.

---

### T33 [2] [GREEN] Implement `lib/features/coach/presentation/widgets/location_permission_rationale_sheet.dart`

- **Files**: `lib/features/coach/presentation/widgets/location_permission_rationale_sheet.dart` (NEW)
- **REQs**: REQ-COACH-DISC-UI-011
- **Description**: Implement the bottom sheet content widget with `onAccepted` and `onDismissed` callbacks. Add static `show(BuildContext context) → Future<bool>` helper that calls `showModalBottomSheet` and returns `true` if accepted, `false` if dismissed. Per D8: only shown when permission status is `denied` (not `deniedForever`).
- **Acceptance**: `flutter test test/.../location_permission_rationale_sheet_test.dart` all green.

---

### T34 [2] [RED] Widget tests — `TrainersListScreen`

- **Files**: `test/features/coach/presentation/trainers_list_screen_test.dart` (NEW)
- **SCENARIOs**: SCENARIO-425, SCENARIO-426, SCENARIO-427, SCENARIO-428, SCENARIO-430, SCENARIO-431, SCENARIO-432
- **REQs**: REQ-COACH-DISC-UI-001..011
- **Description**: Define `_pumpListScreen(WidgetTester, {required overrides})` helper using `ProviderScope`. Write failing tests overriding `trainerDiscoveryProvider` and `selectedSpecialtyProvider` directly: (1) `AsyncLoading` → `CircularProgressIndicator` visible, no `TrainerListTile` — SCENARIO-425; (2) `AsyncError` → error text visible, no `TrainerListTile` — SCENARIO-426; (3) empty `AsyncData([])` → empty state message visible — SCENARIO-427; (4) `AsyncData([a, b, c])` → exactly 3 `TrainerListTile` widgets with texts 'Ana', 'Bruno', 'Carla' — SCENARIO-428; (5) chip row has 11 chips, "Todos" selected by default — SCENARIO-430; (6) tap yoga chip → `selectedSpecialtyProvider` updates → only yoga trainers visible — SCENARIO-431; (7) tap tile for `uid: 'trainer-99'` → router navigates to `/coach/trainer/trainer-99` — SCENARIO-432. Screen undefined → tests fail.
- **Acceptance**: `flutter test test/.../trainers_list_screen_test.dart` exits non-zero; 7+ test cases declared.

---

### T35 [2] [GREEN] Implement `lib/features/coach/presentation/trainers_list_screen.dart`

- **Files**: `lib/features/coach/presentation/trainers_list_screen.dart` (NEW)
- **REQs**: REQ-COACH-DISC-UI-001..011
- **Description**: Implement `TrainersListScreen extends ConsumerStatefulWidget` (D22). `initState`: post-frame callback calls `ref.read(athleteLocationProvider.notifier).requestIfNeeded(context)` with `_rationaleShown` guard. `build`: Column with `_Header` (title + `_MapListToggle` using `mapModeProvider`), `TrainerSpecialtyChips` (watching/writing `selectedSpecialtyProvider`), `Expanded` switching on `mapModeProvider`: map-true → stub `Center(Text(CoachStrings.mapComingSoon))`; map-false → `AsyncValue.when` on `trainerDiscoveryProvider` → loading/error/empty/list states. List: `ListView.builder` with `TrainerListTile(trainer: t, distanceKm: _distanceFor(t), onTap: () => context.push('/coach/trainer/\${t.uid}'))`.
- **Acceptance**: `flutter test test/.../trainers_list_screen_test.dart` all green.

---

### T36 [2] [RED] Widget tests — `TrainerPublicProfileScreen`

- **Files**: `test/features/coach/presentation/trainer_public_profile_screen_test.dart` (NEW)
- **SCENARIOs**: SCENARIO-433, SCENARIO-434
- **REQs**: REQ-COACH-DISC-UI-012..017
- **Description**: Define `_pumpProfileScreen(WidgetTester, String uid, {required overrides})` helper. Write failing tests overriding `trainerByIdProvider` directly: (1) `AsyncLoading` → `CircularProgressIndicator`, no hero text; (2) `AsyncError` → error message visible, retry button present; (3) `AsyncData(null)` → `'Perfil no encontrado'` message and back button visible; (4) `AsyncData(trainer)` → `displayName`, specialty, 'RESEÑAS'/'AÑOS EXP'/'ALUMNOS' with '–', bio text, 'PEDIR VÍNCULO' button all visible — SCENARIO-433; (5) tap 'PEDIR VÍNCULO' → `SnackBar` with `'Próximamente — Etapa 3'` shown — SCENARIO-434; (6) back button navigates via `context.pop()` when stack has history. Screen undefined → tests fail.
- **Acceptance**: `flutter test test/.../trainer_public_profile_screen_test.dart` exits non-zero; 6 test cases declared.

---

### T37 [2] [GREEN] Implement `lib/features/coach/presentation/trainer_public_profile_screen.dart`

- **Files**: `lib/features/coach/presentation/trainer_public_profile_screen.dart` (NEW)
- **REQs**: REQ-COACH-DISC-UI-012..017
- **Description**: Implement `TrainerPublicProfileScreen extends ConsumerWidget` with `required String uid` (D23). Watches `trainerByIdProvider(uid)`. States: loading → spinner; error → message + retry (`ref.invalidate`); `data(null)` → `_ProfileNotFound` (text + `context.go('/coach')`); `data(trainer)` → `ListView` with `_BackBar`, `TrainerProfileHero`, `TrainerStatsRow`, bio if non-null, `_HourlyRateBlock` if non-null, `TrainerContactCtaStub(onTap: () → ScaffoldMessenger.showSnackBar(CoachStrings.ctaSnackBar))`. `_onBack`: `context.canPop() ? context.pop() : context.go('/coach')`.
- **Acceptance**: `flutter test test/.../trainer_public_profile_screen_test.dart` all green.

---

### T38 [2] [MOD] `lib/features/coach/athlete_coach_view.dart` — replace stub with `TrainersListScreen`

- **Files**: `lib/features/coach/athlete_coach_view.dart` (MODIFIED)
- **REQs**: REQ-COACH-DISC-UI-001
- **Description**: Remove existing stub body text. Add import for `TrainersListScreen`. Replace stub content with `const TrainersListScreen()`. Existing `athlete_coach_view_test.dart` must be updated to expect `TrainersListScreen` widget presence instead of the old headline/subtitle text.
- **Acceptance**: `flutter test test/features/coach/athlete_coach_view_test.dart` green with updated assertion; `find.byType(TrainersListScreen)` found.

---

### T39 [2] [RED] Router test — `/coach/trainer/:uid` resolves with bottom bar

- **Files**: `test/app/router_coach_routes_test.dart` (NEW)
- **REQs**: REQ-COACH-DISC-UI-018
- **Description**: Create new test file. Write failing tests: (1) navigate to `/coach/trainer/trainer-99` → `find.byType(TrainerPublicProfileScreen)` visible; (2) `find.byType(TreinoBottomBar)` is visible (sub-route is under ShellRoute — D17); wrap router in `ProviderScope` overriding `trainerByIdProvider('trainer-99')` with a stub profile. Route does not exist yet → tests fail.
- **Acceptance**: `flutter test test/app/router_coach_routes_test.dart` exits non-zero; 2 test cases declared.

---

### T40 [2] [GREEN] Add sub-route in `lib/app/router.dart`

- **Files**: `lib/app/router.dart` (MODIFIED)
- **REQs**: REQ-COACH-DISC-UI-018
- **Description**: Add `GoRoute(path: 'trainer/:uid', pageBuilder: (context, state) => _noAnim(TrainerPublicProfileScreen(uid: state.pathParameters['uid']!)))` as a sub-route under the existing `GoRoute(path: '/coach')` inside the `ShellRoute`. Add import for `TrainerPublicProfileScreen` in alphabetical order among coach presentation imports. Pattern mirrors `/feed/profile/:uid`.
- **Acceptance**: `flutter test test/app/router_coach_routes_test.dart` all green; `TreinoBottomBar` visible assertion passes.

---

### T41 [2] [QA] PR2 quality gate

- **Files**: none (command-only)
- **Description**: Run `flutter analyze` (0 issues required), then `dart format .` (no unformatted files), then `flutter test` (full suite green including all PR1 + PR2 tests). BLOCKER — do not open PR2 until all three pass.
- **Acceptance**: All three commands exit 0.

---

## Goal-Backward Coverage

| REQ | SCENARIO(s) | RED task | GREEN task | Gap |
|-----|-------------|----------|------------|-----|
| REQ-COACH-DISC-DATA-001 | 407, 408 | T11 | T12 | None |
| REQ-COACH-DISC-DATA-002 | 407, 408 | T11 | T12 | None |
| REQ-COACH-DISC-DATA-003 | 409, 410 | T09 | T10 | None |
| REQ-COACH-DISC-DATA-004 | 411, 413 | T13 | T14 | None |
| REQ-COACH-DISC-DATA-005 | 412 | T13 | T14 | None |
| REQ-COACH-DISC-DATA-006 | 414 | T13 | T14 | None |
| REQ-COACH-DISC-DATA-007 | 415 | T13 | T14 | None |
| REQ-COACH-DISC-DATA-008 | 416, 417 | T17 (skipped — emulator) | T17 | Emulator-deferred (intentional per D21) |
| REQ-COACH-DISC-DATA-009 | 418, 419 | T17 (skipped — emulator) | T17 | Emulator-deferred (intentional per D21) |
| REQ-COACH-DISC-DATA-010 | 420, 421 | T07 | T08 | None |
| REQ-COACH-DISC-DATA-011 | 422 | T05 | T06 | None |
| REQ-COACH-DISC-DUAL-001 | 423 | T15 | T16 | None |
| REQ-COACH-DISC-DUAL-002 | 424 | T15 | T16 | None |
| REQ-COACH-DISC-UI-001 | (structural — 425 tree) | T38 | T38 | None |
| REQ-COACH-DISC-UI-002 | 425 | T34 | T35 | None |
| REQ-COACH-DISC-UI-003 | 426 | T34 | T35 | None |
| REQ-COACH-DISC-UI-004 | 427 | T34 | T35 | None |
| REQ-COACH-DISC-UI-005 | 428 | T34 | T35 | None |
| REQ-COACH-DISC-UI-006 | 429 | T26 | T27 | None |
| REQ-COACH-DISC-UI-007 | 430 | T28 + T34 | T29 + T35 | None |
| REQ-COACH-DISC-UI-008 | 431 | T28 + T34 | T29 + T35 | None |
| REQ-COACH-DISC-UI-009 | 432 | T34 | T35 | None |
| REQ-COACH-DISC-UI-010 | (smoke — map toggle) | T34 | T35 | None |
| REQ-COACH-DISC-UI-011 | (provider test, T22–T25) | T22 + T24 | T23 + T25 | None |
| REQ-COACH-DISC-UI-012 | (widget test — loading) | T36 | T37 | None |
| REQ-COACH-DISC-UI-013 | (widget test — not-found) | T36 | T37 | None |
| REQ-COACH-DISC-UI-014 | (widget test — error) | T36 | T37 | None |
| REQ-COACH-DISC-UI-015 | 433 | T30 + T36 | T31 + T37 | None |
| REQ-COACH-DISC-UI-016 | 434 | T30 + T36 | T31 + T37 | None |
| REQ-COACH-DISC-UI-017 | (widget test — back nav) | T36 | T37 | None |
| REQ-COACH-DISC-UI-018 | 432, 433 | T39 | T40 | None |

### SCENARIO → Task mapping

| SCENARIO | Task(s) |
|----------|---------|
| 407 | T11 (RED), T12 (GREEN) |
| 408 | T11 (RED), T12 (GREEN) |
| 409 | T09 (RED), T10 (GREEN) |
| 410 | T09 (RED), T10 (GREEN) |
| 411 | T13 (RED), T14 (GREEN) |
| 412 | T13 (RED), T14 (GREEN) |
| 413 | T13 (RED), T14 (GREEN) |
| 414 | T13 (RED), T14 (GREEN) |
| 415 | T13 (RED), T14 (GREEN) |
| 416 | T17 (emulator-skipped stub) |
| 417 | T17 (emulator-skipped stub) |
| 418 | T17 (emulator-skipped stub) |
| 419 | T17 (emulator-skipped stub) |
| 420 | T07 (RED), T08 (GREEN) |
| 421 | T07 (RED), T08 (GREEN) |
| 422 | T05 (RED), T06 (GREEN) |
| 423 | T15 (RED), T16 (GREEN) |
| 424 | T15 (RED), T16 (GREEN) |
| 425 | T34 (RED), T35 (GREEN) |
| 426 | T34 (RED), T35 (GREEN) |
| 427 | T34 (RED), T35 (GREEN) |
| 428 | T34 (RED), T35 (GREEN) |
| 429 | T26 (RED), T27 (GREEN) |
| 430 | T28+T34 (RED), T29+T35 (GREEN) |
| 431 | T28+T34 (RED), T29+T35 (GREEN) |
| 432 | T34+T39 (RED), T35+T40 (GREEN) |
| 433 | T30+T36 (RED), T31+T37 (GREEN) |
| 434 | T30+T36 (RED), T31+T37 (GREEN) |

All SCENARIOs 407..434 land in specific test tasks. No orphan SCENARIOs found.

---

## Task Summary

| Section | Tasks | Focus |
|---------|-------|-------|
| PR1 — CHORE | T01–T04 | Branch + platform config |
| PR1 — RED/GREEN (geohash5) | T05–T06 | `geohash5` unit test cycle |
| PR1 — RED/GREEN (haversine) | T07–T08 | `haversineKm` unit test cycle |
| PR1 — RED/GREEN (specialty enum) | T09–T10 | `TrainerSpecialty` unit test cycle |
| PR1 — RED/GREEN (model) | T11–T12 | `TrainerPublicProfile` unit test cycle |
| PR1 — RED/GREEN (repo) | T13–T14 | `TrainerPublicProfileRepository` repo test cycle |
| PR1 — RED/GREEN (dual-write) | T15–T16 | `UserRepository` integration test cycle |
| PR1 — MOD + stub | T17 | `firestore.rules` + emulator-skipped test stubs |
| PR1 — QA | T18 | analyze + format + full suite |
| **PR1 total** | **18** | |
| PR2 — CHORE | T19–T21 | Branch + `CoachStrings` + icons |
| PR2 — RED/GREEN (location notifier) | T22–T23 | `AthleteLocationNotifier` provider test cycle |
| PR2 — RED/GREEN (discovery provider) | T24–T25 | `trainerDiscoveryProvider` + `trainerByIdProvider` |
| PR2 — RED/GREEN (TrainerListTile) | T26–T27 | Widget test cycle |
| PR2 — RED/GREEN (specialty chips) | T28–T29 | Widget test cycle |
| PR2 — RED/GREEN (profile widgets) | T30–T31 | Hero + StatsRow + CTA test cycle |
| PR2 — RED/GREEN (rationale sheet) | T32–T33 | Bottom sheet test cycle |
| PR2 — RED/GREEN (TrainersListScreen) | T34–T35 | Screen widget test cycle |
| PR2 — RED/GREEN (ProfileScreen) | T36–T37 | Screen widget test cycle |
| PR2 — MOD (AthleteCoachView) | T38 | Replace stub + update existing test |
| PR2 — RED/GREEN (router) | T39–T40 | Router sub-route test cycle |
| PR2 — QA | T41 | analyze + format + full suite |
| **PR2 total** | **23** | |
| **Grand total** | **41** | |

Execution order within each PR is strictly sequential — each RED must be observed failing before its GREEN, each GREEN confirmed passing before the next RED.

*Generated by sdd-tasks — 2026-05-20*
