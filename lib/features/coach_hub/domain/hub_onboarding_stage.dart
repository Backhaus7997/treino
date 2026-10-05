import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_profile_trainer_completeness.dart';
import 'package:treino/features/profile_setup/domain/profile_setup_validators.dart';

/// Etapa del onboarding de un PF que entra al Coach Hub con el perfil
/// incompleto (cuenta web promovida a trainer).
///
/// El orden es el de [hubOnboardingStage]: `age -> identity -> pf -> done`.
enum HubOnboardingStage { age, identity, pf, done }

/// Decide la etapa de [profile]. Función pura: sin Riverpod, sin I/O y sin
/// `DateTime.now()` oculto (`now` entra por parámetro).
///
/// Devuelve la PRIMERA etapa que falle:
/// 1. `age`: `bornAt` inválido o menor de 13 años. Va primero para no guardar
///    el nombre ni el consentimiento de un menor.
/// 2. `identity`: `displayName` ausente o en blanco. NO mira
///    `firstName`/`lastName` ni `termsAcceptedAt`: un PF legacy tiene el handle
///    como `displayName` y exigirlos lo bloquearía el día del deploy.
/// 3. `pf`: `!trainerProfileComplete`.
/// 4. `done`.
HubOnboardingStage hubOnboardingStage(UserProfile profile, {DateTime? now}) {
  if (ProfileSetupValidators.validateBornAt(profile.bornAt, now: now) != null) {
    return HubOnboardingStage.age;
  }
  final name = profile.displayName?.trim() ?? '';
  if (name.isEmpty) {
    return HubOnboardingStage.identity;
  }
  if (!profile.trainerProfileComplete) {
    return HubOnboardingStage.pf;
  }
  return HubOnboardingStage.done;
}
