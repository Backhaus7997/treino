import 'package:freezed_annotation/freezed_annotation.dart';

import 'experience_level.dart';
import 'gender.dart';

part 'profile_setup_draft.freezed.dart';

/// Estado in-memory del flow de ProfileSetup mientras el atleta va completando
/// los 4 steps. No se persiste hasta el último submit (paso "EMPEZAR" en step 4).
///
/// Cuando Etapa 3 (UserProfile + UserRepository) esté lista, el submit final
/// va a mapear este draft a `UserProfile` y escribir en Firestore.
@freezed
class ProfileSetupDraft with _$ProfileSetupDraft {
  const factory ProfileSetupDraft({
    /// Step 1
    String? username,

    /// Step 1 — path local del avatar elegido del image_picker. Se uploadea
    /// a Firebase Storage en el submit final, y la URL resultante se persiste
    /// como `avatarRemoteUrl`.
    String? avatarLocalPath,

    /// Step 1 — URL HTTPS del avatar después del upload a Storage. `null`
    /// mientras el usuario no haya elegido foto o el upload no haya completado.
    String? avatarRemoteUrl,

    /// Step 2 — `null` si el usuario aún no eligió, o [kNoGymId] si optó por
    /// "OTRO GYM / SIN GYM".
    String? gymId,

    /// Step 3
    ExperienceLevel? experience,

    /// Step 3
    Gender? gender,

    /// Step 4 — peso corporal en kilogramos.
    double? weightKg,

    /// Step 4 — altura en centímetros.
    double? heightCm,
  }) = _ProfileSetupDraft;

  const ProfileSetupDraft._();

  /// Step 1 está completo cuando hay username válido. El avatar es opcional
  /// (el atleta puede omitirlo y agregarlo más tarde desde Perfil → Ajustes).
  bool get isStep1Valid {
    final u = username?.trim();
    return u != null && u.length >= 3;
  }

  /// Step 2 está completo cuando el atleta eligió un gym o "OTRO/SIN GYM".
  /// Cualquier opción es válida — no es obligatorio tener gym registrado.
  bool get isStep2Valid => gymId != null;

  /// Step 3 está completo cuando hay experiencia y género elegidos.
  bool get isStep3Valid => experience != null && gender != null;

  /// Step 4 está completo cuando hay peso y altura dentro de rangos plausibles.
  bool get isStep4Valid {
    final w = weightKg;
    final h = heightCm;
    return w != null &&
        w > 20 &&
        w < 300 &&
        h != null &&
        h > 100 &&
        h < 250;
  }

  /// Sólo cuando los 4 steps están completos se habilita el botón "EMPEZAR".
  bool get isComplete =>
      isStep1Valid && isStep2Valid && isStep3Valid && isStep4Valid;
}
