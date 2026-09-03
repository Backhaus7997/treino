// ignore: unused_import — Timestamp is used by the generated user_profile.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../coach/domain/trainer_location.dart';
import '../../coach/domain/trainer_subscription.dart';
import '../../workout/domain/template_preferences.dart';
import '../data/timestamp_converter.dart';
import 'experience_level.dart';
import 'gender.dart';
import 'user_role.dart';

part 'user_profile.freezed.dart';
part 'user_profile.g.dart';

@freezed
class UserProfile with _$UserProfile {
  /// `displayName` is intentionally nullable: signup/signin create the doc
  /// with `null`, and ProfileSetup (Etapa 6) is responsible for populating it.
  /// Etapa 2 signup MUST NOT carry a name — that violates REQ-AUTH-002.
  ///
  /// Trainer-specific fields (`trainerBio`, `trainerSpecialty`,
  /// `trainerLatitude`, `trainerLongitude`, `trainerGeohash`,
  /// `trainerMonthlyRate`) son nullable y solo se setean cuando
  /// `role == UserRole.trainer`. La extensión propia del onboarding del
  /// PF llega en Fase 5 Etapa 2 (Discovery). Esta etapa solo agrega los
  /// campos al schema — sin escribirlos.
  const factory UserProfile({
    required String uid,
    required String email,
    required String? displayName,
    required UserRole role,
    @TimestampConverter() required DateTime createdAt,
    @TimestampConverter() required DateTime updatedAt,
    String? gymId,
    double? bodyWeightKg,
    int? heightCm,
    Gender? gender,
    ExperienceLevel? experienceLevel,
    String? avatarUrl,
    // ── Datos personales estructurados (Coach Hub web W3.1b) ──────────────
    // `firstName`/`lastName` son la fuente de los campos Nombre/Apellido del
    // form de Cuenta del Coach Hub. `displayName` (usado en roster + perfil
    // público) se DERIVA de ambos al guardar, para no romper a quien ya lo
    // consume. `phone` es privado: NO se propaga a userPublicProfiles.
    String? firstName,
    String? lastName,
    String? phone,
    @TimestampConverter() DateTime? bornAt,
    // ── Consentimiento legal (QA-AUTH-001, issue #434) ────────────────────
    // Instante de aceptación de Términos y Política de Privacidad. Email:
    // escrito por signUpWithEmail (el gate del checkbox vive en Register).
    // OAuth: escrito por el submit de ProfileSetup (checkbox obligatorio para
    // cuentas nuevas). Null ⇒ cuenta legacy pre-feature (sin evidencia).
    @TimestampConverter() DateTime? termsAcceptedAt,
    // ── Consentimiento legal versionado (consentimiento-legal-versionado) ─
    // `acceptedTermsVersion` / `acceptedPrivacyVersion`: qué VERSIÓN de cada
    // documento aceptó, sellada en la misma escritura que `termsAcceptedAt`
    // en cada uno de los 3 caminos de aceptación (signup email, submit de
    // ProfileSetup, `UserRepository.getOrCreate`). `null` ⇒ cuenta legacy
    // sin evidencia versionada — NUNCA se trata como "aceptó la versión 0"
    // ni "aceptó la vigente".
    //
    // `trainerLocationConsentAt` / `trainerLocationConsentPromptedAt` son un
    // consentimiento DISTINTO e independiente del gate de versión de arriba:
    // habilitan la publicación de la ubicación del PF en el mapa. Se
    // disparan recién en la promoción a `trainer`, nunca en signup ni en
    // ninguna escritura de aceptación de T&C/Privacidad — un atleta que
    // aceptó la Política vigente y es promovido después IGUAL necesita este
    // consentimiento aparte (spec: comparar sólo versiones no cubre ese
    // caso).
    //
    // Tabla de estados (el contrato — cualquier gate que lea estos 2 campos
    // debe resolver exactamente esto):
    //
    // | consentAt | promptedAt | Significado                        | ¿Sheet? | Ubicación publicada |
    // |-----------|------------|-------------------------------------|---------|----------------------|
    // | null      | null       | nunca preguntado / legacy            | sí      | sí (status quo)      |
    // | set       | set        | otorgado                             | no      | sí                   |
    // | null      | set        | preguntado y no otorgado (cerró/apagó)| no     | según el espejo      |
    // | set       | null       | imposible por construcción — tratar como otorgado | no | sí |
    //
    // `promptedAt` es el campo anti-loop: responde "¿ya se lo preguntamos?",
    // no "¿consintió?". Es lo único que gatea el re-display del sheet —
    // NUNCA `trainerLocations.isNotEmpty` (ese es sólo un filtro de
    // relevancia: revocar no vacía `trainerLocations` en `users/`, así que
    // gatear por ahí reabriría el sheet en cada arranque).
    int? acceptedTermsVersion,
    int? acceptedPrivacyVersion,
    @TimestampConverter() DateTime? trainerLocationConsentAt,
    @TimestampConverter() DateTime? trainerLocationConsentPromptedAt,
    // ── Trainer-specific (Fase 5 Etapa 1 foundations) ───────────────────
    String? trainerBio,
    String? trainerSpecialty,
    int? trainerMonthlyRate,
    String? paymentAlias,
    // Años de experiencia del PF (#388). Opcional — lo carga el propio PF
    // desde el form de perfil profesional y se propaga a
    // trainerPublicProfiles vía dual-write. Null ⇒ el perfil público muestra
    // el placeholder "—" en la tile AÑOS EXP.
    int? trainerExperienceYears,

    // ── Multi-location (Fase 6 Etapa 0) ────────────────────────────────
    //
    // `trainerLatitude/Longitude/Geohash` (singulares, marcados DEPRECATED)
    // se mantienen por backward compat — clientes viejos siguen leyendo el
    // campo legacy hasta que actualicen. La migration de `treino-dev`
    // (scripts/migrate_trainer_locations.js) convierte cada doc legacy a
    // `trainerLocations: [{type: custom OR gym, ...}]`. Cleanup PR borra
    // los campos legacy cuando todas las clientes estén en la versión nueva.
    //
    // `trainerLocations` mezcla gyms del catálogo (`type == gym`, `gymId`
    // referencia `gyms/{gymId}`) y lugares propios (`type == custom`,
    // `customLabel` lleva el nombre).
    //
    // `trainerGeohashes` es array derivado en write-time desde
    // `trainerLocations` — necesario para el query
    // `where('trainerGeohashes', array-contains-any, [vecinos del atleta])`
    // que reemplaza el `where('trainerGeohash', >=, prefix5)` original.
    //
    // `trainerOffersOnline` es flag independiente. La combinación
    // `trainerLocations.isEmpty && !trainerOffersOnline` es inválida —
    // UserRepository.update() la rechaza con ArgumentError antes del write.
    double? trainerLatitude, // DEPRECATED
    double? trainerLongitude, // DEPRECATED
    String? trainerGeohash, // DEPRECATED
    @Default(<TrainerLocation>[]) List<TrainerLocation> trainerLocations,
    @Default(<String>[]) List<String> trainerGeohashes,
    @Default(false) bool trainerOffersOnline,

    // ── Athlete active routine (home today's card PR#2) ───────────────────
    // Points to the user-created routine the athlete picked as "the one I'm
    // currently training". Used by [todaysRoutineProvider] to resolve the home
    // card when the user has multiple self-created routines and no trainer
    // plan. Null when no active routine is set (single routine auto-activates,
    // multi without selection shows the empty CTA). Setting/unsetting is
    // toggled from the overflow menu of each card in MisRutinasSection.
    String? activeRoutineId,

    // ── Paywall subscription (Fase 7 PR1) ──────────────────────────────
    // Suscripción del PF a TREINO. `null`/ausente ⇒ Free (sin backfill,
    // ver trainer_subscription.dart). CF-write-only (firestore.rules pin);
    // el cliente nunca escribe `subscription` ni `weightedLoad`.
    // `weightedLoad` es la carga ponderada denormalizada (activos=1.0,
    // pausados=0.5) que el CF mantiene para que UI/rules lean sin agregar.
    TrainerSubscription? subscription,
    double? weightedLoad,

    // ── Welcome tour seen-flags (issue #627) ────────────────────────────
    // Map of `OnboardingSurface.wireKey` → version of the tour that user
    // has already seen on that surface. Absent/empty ⇒ nothing seen yet, so
    // existing accounts need no backfill and no migration.
    //
    // ONE ENTRY PER SURFACE, not a single global flag: a trainer who saw the
    // mobile tour must still get the Coach Hub web one. Versioned per entry so
    // a future redesign can re-show a single surface without touching data.
    //
    // Owner-writeable and owner-read only — no Cloud Function, no rules change
    // (`users/{uid}` has no key allowlist; see firestore.rules:65-80).
    // Read via `OnboardingSurface.shouldShow`, written via
    // `OnboardingSurface.markedIn` — never index this map with a raw string.
    @Default(<String, int>{}) Map<String, int> onboardingSeen,

    // ── PLANTILLAS mini-onboarding answers (issue #635) ─────────────────
    // Días, minutos, objetivo y zonas que el atleta declaró la primera vez que
    // entró a PLANTILLAS. Null/ausente ⇒ todavía no lo respondió; no hay
    // backfill ni migración, igual que `onboardingSeen`.
    //
    // PRIVADO: son preferencias del atleta, no parte de su perfil público. No
    // se propagan a `userPublicProfiles` — ese path tiene su propio allowlist
    // explícito de claves en firestore.rules, así que no puede filtrarse solo.
    //
    // `users/{uid}` no tiene guarda `hasOnly` en update (firestore.rules:65-80),
    // así que este campo NO requiere cambio de reglas. El acoplamiento del
    // COUPLING WARNING es de los paths de `routines`, no de este.
    TemplatePreferences? templatePreferences,
  }) = _UserProfile;

  factory UserProfile.fromJson(Map<String, Object?> json) =>
      _$UserProfileFromJson(json);
}
