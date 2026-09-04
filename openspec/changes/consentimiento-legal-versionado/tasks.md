# Tasks: consentimiento-legal-versionado

**Branch**: `feat/consentimiento-legal-versionado` (sobre `origin/main`) · **Modo**: single-PR + `size:exception` (ya aceptado) · **Sin issue linkeado** · Label sugerido: `type:feature` + `size:exception`.

## Review Workload Forecast

| Field | Value |
|---|---|
| Estimated changed lines | ~690 (design.md: base ~660 + ~25-30 del 4º campo `trainerLocationConsentPromptedAt`) |
| 400-line budget risk | High |
| Chained PRs recommended | No — decisión explícita del usuario, no partir |
| Suggested split | Single PR, 12 commits por unidad de trabajo (ver abajo) |
| Delivery strategy | single-pr |
| Chain strategy | size-exception |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: size-exception
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | PR | Notes |
|---|---|---|---|
| 1. Foundation | constantes + 4 campos + regen freezed | PR1 (single) | bloquea todo lo demás |
| 2. Repo core | gate del subset, grant/revoke, getOrCreate | PR1 (single) | depende de 1 |
| 3. Acceptance paths | signup email + ProfileSetup estampan versión | PR1 (single) | depende de 1 (2 sólo para `getOrCreate`) |
| 4. Trainer consent UI | providers + sheet + gate en Home + form PF | PR1 (single) | depende de 1-2 |
| 5. Aviso atleta | notice no bloqueante | PR1 (single) | sólo depende de 1 — paralelizable con 2-4 |
| 6. Verificación | analyze/format/tests/rules-diff/device | PR1 (single) | al final |

**Leyenda de requirements** — R1-R9 de `specs/legal-consent-versioning/spec.md`, T1-T2 de `specs/trainer-profile-onboarding/spec.md`:

| Tag | Requirement |
|---|---|
| R1 | Independent Monotonic Version Constants |
| R2 | Per-Document Accepted-Version Fields on UserProfile |
| R3 | Version Stamping at Every Acceptance Path |
| R4 | Non-Blocking Legacy Notice for Athletes |
| R5 | Consent Tracks "Granted" separate de "Asked" |
| R6 | Location Publication Requires Effective Consent at Write Time |
| R7 | Consent Prompt: 3 salidas, sin dismiss accidental |
| R8 | Grant/Revoke explícitos, mirror asimétrico |
| R9 | Evidence, not a rules boundary (`firestore.rules` intacto) |
| T1 | Revocation nunca pisa el partial-key gap del guard |
| T2 | `profile_edit_trainer_screen` pide consentimiento + muestra estado real |

---

## 1. `feat(auth): sumar kTermsVersion/kPrivacyVersion/kPrivacyV1PublishedAt`

- [x] 1.1 RED — nuevo `test/features/auth/presentation/legal/legal_content_test.dart`: `kTermsVersion==1`, `kPrivacyVersion==1` (ambas `int`, independientes — bumpear una no toca la otra); `kPrivacyV1PublishedAt == DateTime.utc(2026,9,3)`. **[R1]**
- [x] 1.2 GREEN — `lib/features/auth/presentation/legal/legal_content.dart`: agregar las 3 constantes + dartdoc (distinguir de `kPrivacyLastUpdated`, que nunca se parsea). **[R1]**

## 2. `feat(profile): sumar 4 campos de consentimiento a UserProfile`

Depende de: nada (paralelizable con 1).

- [x] 2.1 RED — extender `test/features/profile/domain/user_profile_test.dart`: round-trip `fromJson`/`toJson` de `acceptedTermsVersion`, `acceptedPrivacyVersion`, `trainerLocationConsentAt`, `trainerLocationConsentPromptedAt`; ausente ⇒ `null`. **[R2]**
- [x] 2.2 GREEN — `lib/features/profile/domain/user_profile.dart`: agregar los 4 campos nullable + dartdoc con la tabla de estados (design D-B). **[R2]**

## 3. `chore(profile): regenerar user_profile.freezed.dart/.g.dart`

Depende de: 2.2. **Bloquea 4, 5, 6, 7, 8, 9** (cualquier código que construya/lea un `UserProfile` con los campos nuevos necesita el output regenerado para compilar).

- [x] 3.1 `dart run build_runner build --delete-conflicting-outputs`. Commit SOLO el output generado (~90-110 líneas), sin código de mano — mantiene el diff generado auditable por separado.

## 4. `feat(profile): gatear el dual-write de ubicación por consentimiento efectivo`

Depende de: 3.

- [x] 4.1 RED — nuevo `test/features/profile/data/user_repository_trainer_location_consent_test.dart` (mirror de `user_repository_trainer_dual_write_test.dart`: `FakeFirebaseFirestore` + `seedDoc`): partial con `trainerLocations` + `trainerBio`, `consentAt==null` ⇒ `trainerPublicProfiles` NO recibe claves de ubicación pero SÍ `trainerBio`/`trainerMonthlyRate`/`trainerOffersOnline` (anti-republish — el caso que descalifica la opción (b)). **[R6]**
- [x] 4.2 RED — mismo archivo: `consentAt` ya guardado (no en el partial) ⇒ `trainerPublicProfiles` SÍ recibe `trainerLocations` (consentimiento efectivo = partial sobre lo guardado). **[R6]**
- [x] 4.3 GREEN — `lib/features/profile/data/user_repository.dart`: `_trainerPublicSubsetFromPartial` gana `required bool hasLocationConsent`; `update()` resuelve el consentimiento efectivo (valor del partial si está, si no un `get()` — sólo cuando el partial trae `trainerLocations`/`trainerGeohashes`, nunca en camino caliente). **[R6]**
  - Nota de implementación: el gate sólo filtra `trainerLocations`/`trainerGeohashes` (el modelo multi-location activo). Los 3 campos singulares deprecados (`trainerLatitude`/`trainerLongitude`/`trainerGeohash`) quedan SIN gatear — nunca los escribe código productivo (`profile_edit_trainer_screen.dart` siempre los manda `null`) y gatearlos rompía 3 tests preexistentes sin ningún escenario de spec que los ejercite bajo el gate nuevo. Ver riesgos del apply-progress.
  - Actualizados 4 tests preexistentes en `user_repository_trainer_dual_write_test.dart` (grupo "multi-location dual-write") que asumían el dual-write de ubicación sin consentimiento — ver commit 4 para el detalle.

## 5. `feat(profile): grantTrainerLocationConsent/revokeTrainerLocationConsent`

Depende de: 3 (puede ir en paralelo con 4, mismo archivo pero método distinto).

- [x] 5.1 RED — mismo test file de 4: `revokeTrainerLocationConsent` no lanza; `users/{uid}.trainerLocations` y `.trainerOffersOnline` quedan intactos; el partial escrito a `users/` tiene SOLO `trainerLocationConsentAt`/`trainerLocationConsentPromptedAt` (cero `trainerLocations`/`trainerOffersOnline` — cierra el guard-gap). **[R8][T1]**
- [x] 5.2 RED — mismo archivo: tras revocar, `trainerPublicProfiles` pierde las 5 claves de ubicación y `trainerOffersOnline` queda intacto. **[R8]**
- [x] 5.3 RED — mismo archivo: `grantTrainerLocationConsent` re-espeja las `trainerLocations` ya guardadas en `users/` hacia `trainerPublicProfiles` (no sólo el timestamp — evita "consentido pero invisible"). **[R8]**
- [x] 5.4 GREEN — `lib/features/profile/data/user_repository.dart`: agregar los 2 métodos explícitos, cada uno un solo `batch.commit()`. **[R8][T1]**

## 6. `feat(profile): getOrCreate estampa versión de T&C y Privacidad`

Depende de: 3.

- [x] 6.1 RED — extender `test/features/profile/data/user_repository_test.dart` (junto al test `getOrCreate with termsAcceptedAt persists it...`, ~línea 78): con `termsAcceptedAt` seteado, el doc también persiste `acceptedTermsVersion==kTermsVersion` y `acceptedPrivacyVersion==kPrivacyVersion`. **[R3]**
- [x] 6.2 GREEN — `lib/features/profile/data/user_repository.dart`: `getOrCreate` gana params `int? acceptedTermsVersion`/`int? acceptedPrivacyVersion` (mismo patrón nullable que `termsAcceptedAt`) y los estampa en el `UserProfile` creado. **[R3]**

## 7. `feat(auth): estampar versión de T&C/Privacidad en el signup por email`

Depende de: 1, 6.

- [x] 7.1 RED — extender `test/features/auth/data/auth_service_test.dart`: `signUpWithEmail` persiste `acceptedTermsVersion`/`acceptedPrivacyVersion` junto a `termsAcceptedAt`. **[R3]**
- [x] 7.2 GREEN — `lib/features/auth/data/auth_service.dart` (~línea 89-96): pasar `acceptedTermsVersion: kTermsVersion, acceptedPrivacyVersion: kPrivacyVersion` al `getOrCreate`. **[R3]**
  - También actualizados los stubs de `mockRepo.getOrCreate` en `auth_service_test.dart` (4 sitios) y `auth_service_signup_verification_orphan_test.dart` (2 sitios) — el nuevo arg de 5 named params dejaba de matchear los stubs de 3.

## 8. `feat(profile): estampar versión de T&C/Privacidad en el submit de ProfileSetup`

Depende de: 1 (NO de 6: este camino usa `update()` genérico, no `getOrCreate`). Paralelizable con 7.

- [x] 8.1 RED — extender `test/features/profile_setup/application/profile_setup_notifier_test.dart`: cuando `needsTermsConsent`, el partial también lleva `acceptedTermsVersion`/`acceptedPrivacyVersion`. **[R3]**
- [x] 8.2 GREEN — `lib/features/profile_setup/application/profile_setup_notifier.dart` (:333): agregar las 2 claves al mismo `if (needsTermsConsent)` que ya escribe `termsAcceptedAt`. **[R3]**

## 9. `feat(profile): providers del gate de consentimiento de ubicación del PF`

Depende de: 3.

- [x] 9.1 RED — nuevo `test/features/profile/application/trainer_location_consent_providers_test.dart` (`ProviderContainer` + perfil fake, mirror de `onboarding_providers_test.dart`): las 4 filas de la tabla de estados (design D-B); atleta ⇒ `false` sea cual sea el resto; `consentAt` set + `promptedAt` null ⇒ tratado como otorgado (edge case explícito de la spec). **[R5]**
- [x] 9.2 GREEN — nuevo `lib/features/profile/application/trainer_location_consent_providers.dart`: `trainerLocationConsentDismissedProvider` (mirror `OnboardingDismissed`, session, uid-scoped) + `shouldAskTrainerLocationConsentProvider` (`role==trainer && trainerLocations.isNotEmpty && consentAt==null && promptedAt==null`, `select()` de los 4 campos — AGENTS.md §6). **[R5]**

## 10. `feat(profile): sheet de consentimiento de ubicación del PF + gate en Home`

Depende de: 5, 9.

- [x] 10.1 RED — nuevo `test/features/profile/presentation/trainer_location_consent_sheet_test.dart` — SOLO estado/semántica (`google_fonts` no carga en `flutter_test`: nada de anchos/wrap/overflow): ACEPTAR llama `grant`, APAGAR llama `revoke`, cerrar (drag/back) sólo marca `promptedAt`; ninguna de las 3 reabre el sheet. **[R7]**
  - "Cerrar por drag/back" testeado simulando back vía `NavigatorState.maybePop()` (no un gesto de arrastre real — ver gotcha de testing del repo sobre `tester.drag`); el `PopScope` del sheet intercepta ambos caminos por igual.
- [x] 10.2 GREEN — nuevo `lib/features/profile/presentation/trainer_location_consent_sheet.dart`: sheet (`isDismissible:false`, `enableDrag:true` — mismo patrón que `custom_exercise_onboarding_gate.dart:122-155`) + `TrainerLocationConsentGate` (`ConsumerStatefulWidget`, mirror de `OnboardingGate`: latch por uid, `addPostFrameCallback`, espera `!ref.watch(onboardingBlocksProvider)` igual que `permission_gate.dart:49-51`). **[R7]**
- [x] 10.3 GREEN — `lib/features/home/home_screen.dart`: montar `const TrainerLocationConsentGate()` en el `Stack` junto a `PermissionGate`/`OnboardingGate` (líneas 63/68). **[R7]**
- [x] 10.4 Copy — claves nuevas en `lib/l10n/intl_es.arb`, `intl_en.arb`, `intl_es_AR.arb` (placeholder; `generate: true` en pubspec regenera `app_l10n*.dart` — NO editar esos `.dart` a mano). **[R7]**

## 11. `feat(profile): pedir consentimiento antes del primer publish + fila de estado`

Depende de: 3, 5 (NO de 10 — confirmación propia más liviana que el sheet completo, no el sheet reusado).

- [x] 11.1 RED — nuevo `test/features/profile/presentation/profile_edit_trainer_screen_test.dart`: (a) `_locations` vacío→no-vacío + `consentAt==null` al guardar ⇒ pide consentimiento antes de persistir; si cancela, no se pierde en silencio; (b) tras revocar (`users` con locations, `trainerPublicProfiles` sin ellas) la fila de estado muestra "no publicado". Estado/semántica, no texto exacto. **[T2]**
- [x] 11.2 GREEN — `lib/features/profile/presentation/profile_edit_trainer_screen.dart`: en `_save()` (~186-207), si `_locations` pasa de vacío a no-vacío y `trainerLocationConsentAt==null` ⇒ confirmación inline que llama `grantTrainerLocationConsent(uid)` antes de `repo.update`; en `build()` (~232+), fila de estado leyendo `profile.trainerLocationConsentAt` vs `profile.trainerLocations`. **[T2]**
- [x] 11.3 Copy — claves nuevas en los 3 `.arb` para la confirmación/fila. **[T2]**

## 12. `feat(profile): aviso no bloqueante de política actualizada para atletas legacy`

Depende de: 1. Paralelizable con 2-11 (no comparte código con la rama de consentimiento del PF).

- [x] 12.1 RED — nuevo test de provider: gate `role==athlete && termsAcceptedAt!=null && termsAcceptedAt.isBefore(kPrivacyV1PublishedAt)`; atleta al día ⇒ `false`; PF ⇒ `false`. **[R4]**
- [x] 12.2 RED — nuevo widget test: el banner no bloquea navegación ni ninguna acción (semántica, no layout). **[R4]**
- [x] 12.3 GREEN — nuevo `lib/features/profile/presentation/legacy_privacy_notice_banner.dart`: provider del gate + banner, montado en `home_screen.dart` `Stack`. **[R4]**
- [x] 12.4 Copy — claves nuevas en los 3 `.arb`. **[R4]**

## 13. Verificación final (no es un commit de producto — corre antes de abrir el PR)

- [ ] 13.1 `flutter analyze` → 0 issues sobre todo lo tocado.
- [ ] 13.2 `dart format` SOLO los archivos de este change — NUNCA `dart format .` (reformatea ~1195 líneas ajenas por drift del SDK, sin gate de formato en CI).
- [ ] 13.3 Correr sólo los tests afectados por path (no `flutter test` pelado — la suite completa tarda ~40 min).
- [ ] 13.4 `git diff --stat firestore.rules` vacío — confirma **[R9]** (evidencia, no frontera de reglas; no se toca).
- [ ] 13.5 Pase manual en device/emulador del sheet y la fila de estado — ningún widget test cubre ancho/wrap/overflow de texto (`google_fonts` no carga en `flutter_test`).

---

## No tocar (recordatorio, no re-litigar)

`firestore.rules` · `_assertTrainerLocationStateIsValid` · `promote_user_to_trainer.js` · `treino-dev` (es producción, cero escrituras).
