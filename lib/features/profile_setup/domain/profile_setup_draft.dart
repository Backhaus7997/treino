import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/domain/experience_level.dart';
import '../../profile/domain/gender.dart';

part 'profile_setup_draft.freezed.dart';

/// Estado in-memory del flow de ProfileSetup mientras el atleta va completando
/// los 4 steps. No se persiste hasta el último submit (paso "EMPEZAR" en step 4).
///
/// En el submit, este draft se mapea a un `UserRepository.update` parcial
/// sobre el `UserProfile` que ya existe en Firestore (creado por
/// `AuthService.signUpWithEmail` al hacer signup via `getOrCreate`). Los
/// campos `uid`, `email`, `role`, `createdAt` viven en UserProfile y son
/// inmutables — el draft no los maneja.
@freezed
class ProfileSetupDraft with _$ProfileSetupDraft {
  const factory ProfileSetupDraft({
    /// Step 1 — mapea a `UserProfile.displayName`.
    String? username,

    /// Step 1 — path local del avatar elegido. Se uploadea a Firebase Storage
    /// en el submit final, y la URL resultante se persiste como
    /// `UserProfile.avatarUrl`.
    String? avatarLocalPath,

    /// Step 2 — `null` si el usuario aún no eligió, o [kNoGymId] si optó por
    /// "OTRO GYM / SIN GYM". Mapea a `UserProfile.gymId` (null en ambos casos).
    String? gymId,

    /// Step 3 — mapea a `UserProfile.experienceLevel`.
    ExperienceLevel? experienceLevel,

    /// Step 3 — mapea a `UserProfile.gender`.
    Gender? gender,

    /// Step 4 — peso corporal en kilogramos. Mapea a `UserProfile.bodyWeightKg`.
    double? bodyWeightKg,

    /// Step 4 — altura en centímetros (entera). Mapea a `UserProfile.heightCm`.
    int? heightCm,
  }) = _ProfileSetupDraft;

  const ProfileSetupDraft._();

  /// Step 1 está completo cuando hay username válido. Avatar es opcional.
  bool get isStep1Valid {
    final u = username?.trim();
    return u != null && u.length >= 3;
  }

  /// Step 2 está completo cuando el atleta eligió un gym o "OTRO/SIN GYM".
  bool get isStep2Valid => gymId != null;

  /// Step 3 está completo cuando hay experiencia y género elegidos.
  bool get isStep3Valid => experienceLevel != null && gender != null;

  /// Step 4 está completo cuando hay peso y altura dentro de rangos plausibles.
  bool get isStep4Valid {
    final w = bodyWeightKg;
    final h = heightCm;
    return w != null && w > 20 && w < 300 && h != null && h > 100 && h < 250;
  }

  bool get isComplete =>
      isStep1Valid && isStep2Valid && isStep3Valid && isStep4Valid;
}
