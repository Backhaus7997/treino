import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/domain/experience_level.dart';
import '../../profile/domain/gender.dart';
import 'profile_setup_validators.dart';

part 'profile_setup_draft.freezed.dart';

/// Estado in-memory del flow de ProfileSetup mientras el atleta va completando
/// los 5 steps. No se persiste hasta el último submit (paso "EMPEZAR" en step 5).
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

    /// Step 2 — fecha de nacimiento. Mapea a `UserProfile.bornAt`.
    ///
    /// OBLIGATORIO, a diferencia del resto de los campos del draft: es el gate
    /// de edad mínima de la cuenta. Ver `ProfileSetupValidators.kMinAgeYears`.
    DateTime? bornAt,

    /// Step 3 — `null` si el usuario aún no eligió, o [kNoGymId] si optó por
    /// "OTRO GYM / SIN GYM". Mapea a `UserProfile.gymId` (null en ambos casos).
    String? gymId,

    /// Step 4 — mapea a `UserProfile.experienceLevel`.
    ExperienceLevel? experienceLevel,

    /// Step 4 — mapea a `UserProfile.gender`.
    Gender? gender,

    /// Step 5 — peso corporal en kilogramos. Mapea a `UserProfile.bodyWeightKg`.
    double? bodyWeightKg,

    /// Step 5 — altura en centímetros (entera). Mapea a `UserProfile.heightCm`.
    int? heightCm,
  }) = _ProfileSetupDraft;

  const ProfileSetupDraft._();

  /// Step 1 está completo cuando hay username válido. Avatar es opcional.
  bool get isStep1Valid {
    final u = username?.trim();
    return u != null && u.length >= 3;
  }

  /// Step 2 está completo cuando la fecha de nacimiento pasa el gate de edad.
  ///
  /// Delega en el validador en vez de repetir la cuenta acá: si la navegación
  /// y el mensaje de error no salen de la misma función, el día que uno cambie
  /// el botón SIGUIENTE habilita una fecha que la pantalla marca en rojo.
  bool get isStep2Valid =>
      ProfileSetupValidators.validateBornAt(bornAt) == null;

  /// Step 3 está completo cuando el atleta eligió un gym o "OTRO/SIN GYM".
  bool get isStep3Valid => gymId != null;

  /// Step 4 está completo cuando hay experiencia y género elegidos.
  bool get isStep4Valid => experienceLevel != null && gender != null;

  /// Step 5 está completo cuando hay peso y altura dentro de rangos plausibles.
  bool get isStep5Valid {
    final w = bodyWeightKg;
    final h = heightCm;
    return w != null && w > 20 && w < 300 && h != null && h > 100 && h < 250;
  }

  bool get isComplete =>
      isStep1Valid &&
      isStep2Valid &&
      isStep3Valid &&
      isStep4Valid &&
      isStep5Valid;
}
