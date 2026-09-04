import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/user_role.dart';
import 'user_providers.dart';

/// consentimiento-legal-versionado — R5, R7.
///
/// Session-scoped, uid-scoped dismissal for the trainer location-consent
/// prompt. Mirrors `OnboardingDismissed`
/// (`../../onboarding/application/onboarding_providers.dart`), for the same
/// two reasons:
///
///  1. Race guard. `userProfileProvider` is a stream: between the sheet's
///     close (accept/revoke/deliberate-close all write `promptedAt`) and the
///     arrival of the updated snapshot, the persisted `promptedAt` still
///     reads `null` and the prompt would push on top of itself.
///  2. Failure guard. If the write never lands (offline), the prompt does
///     not reappear within THIS session — it simply retries on the next
///     cold start.
///
/// Scoped to the uid, not the process, for the same reason
/// `OnboardingDismissed` is: a second trainer signing in on the same device
/// must still get their own prompt.
class TrainerLocationConsentDismissed extends Notifier<bool> {
  @override
  bool build() {
    // The uid, not the profile: re-run — and reset — on account change and
    // ONLY on account change.
    ref.watch(userProfileProvider.select((p) => p.valueOrNull?.uid));
    return false;
  }

  void markDismissed() => state = true;
}

final trainerLocationConsentDismissedProvider =
    NotifierProvider<TrainerLocationConsentDismissed, bool>(
  TrainerLocationConsentDismissed.new,
);

/// Whether the trainer location-consent prompt should be shown right now.
///
/// Tabla de estados (contrato completo en el dartdoc de
/// `UserProfile.trainerLocationConsentAt`, design D-B):
///
/// | consentAt | promptedAt | Significado                             | ¿Sheet? |
/// |-----------|------------|------------------------------------------|---------|
/// | null      | null       | nunca preguntado / legacy                 | sí      |
/// | set       | set        | otorgado                                  | no      |
/// | null      | set        | preguntado y no otorgado (cerró/apagó)    | no      |
/// | set       | null       | imposible por construcción — otorgado     | no      |
///
/// `trainerLocations.isNotEmpty` es un filtro de RELEVANCIA (nada que
/// consentir sin ubicaciones) — NUNCA el cortacircuito de "ya resuelto".
/// `promptedAt` es lo único que gatea el re-display: un PF que revocó
/// sigue teniendo `trainerLocations` no-vacío en `users/{uid}` (revoke no
/// lo toca — ver `UserRepository.revokeTrainerLocationConsent`), así que
/// gatear por `isNotEmpty` reabriría el sheet en cada arranque.
///
/// Deliberadamente NO espera `onboardingBlocksProvider` acá — eso vive en
/// el gate widget (`TrainerLocationConsentGate`), igual que `PermissionGate`
/// lo consulta en su propio `build()` en vez de bakearlo en un provider de
/// "shouldRequestPermission". Mantiene esta lógica pura y sin acoplarse a
/// las preocupaciones de onboarding.
final shouldAskTrainerLocationConsentProvider = Provider<bool>((ref) {
  if (ref.watch(trainerLocationConsentDismissedProvider)) return false;

  // select() sobre los 4 campos relevantes — AGENTS.md §6. El record tiene
  // igualdad por valor, así que este provider sólo re-emite cuando alguno
  // de los 4 realmente cambia, no en cada emisión del perfil completo.
  final fields = ref.watch(
    userProfileProvider.select((async) {
      final p = async.valueOrNull;
      if (p == null) return null;
      return (
        role: p.role,
        hasLocations: p.trainerLocations.isNotEmpty,
        consentAt: p.trainerLocationConsentAt,
        promptedAt: p.trainerLocationConsentPromptedAt,
      );
    }),
  );
  if (fields == null) return false;

  if (fields.role != UserRole.trainer) return false;
  if (!fields.hasLocations) return false;
  return fields.consentAt == null && fields.promptedAt == null;
});
