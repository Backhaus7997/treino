// ignore: unused_import — Timestamp is used by the generated user_profile.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../coach/domain/trainer_location.dart';
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
    // ── Trainer-specific (Fase 5 Etapa 1 foundations) ───────────────────
    String? trainerBio,
    String? trainerSpecialty,
    int? trainerMonthlyRate,
    String? paymentAlias,

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
  }) = _UserProfile;

  factory UserProfile.fromJson(Map<String, Object?> json) =>
      _$UserProfileFromJson(json);
}
