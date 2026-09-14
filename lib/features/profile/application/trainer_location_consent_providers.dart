import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coach/application/trainer_discovery_providers.dart';
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

/// ¿La ubicación del PF está publicada AHORA MISMO? — P1-b.
///
/// Resuelve la columna "¿Ubicación publicada?" de la misma tabla de estados de
/// arriba, que es la única pregunta que la fila de estado del perfil
/// profesional puede contestar sin mentir.
///
/// | consentAt | promptedAt | Ubicación publicada  |
/// |-----------|------------|----------------------|
/// | null      | null       | sí (status quo)      |
/// | set       | set        | sí                   |
/// | null      | set        | **según el espejo**  |
/// | set       | null       | sí                   |
///
/// TRES filas se contestan con los dos timestamps. La cuarta —`consentAt` en
/// null con `promptedAt` seteado, o sea "cerró el sheet sin decidir"— no se
/// puede contestar sin LEER el espejo: cerrar sin decidir escribe únicamente
/// `promptedAt` (ver `TrainerLocationConsentSheet._stampPromptedOnly`) y deja
/// `trainerPublicProfiles` intacto, así que el PF sigue publicado con
/// `consentAt` en null.
///
/// La pantalla resolvía las cuatro filas con `consentAt != null` a secas. Eso
/// colapsa dos filas distintas contra "No publicada": la del que cerró sin
/// decidir —coordenadas que cualquier atleta sigue viendo en el mapa— y la del
/// PF legacy `(null, null)`, que por status quo también sigue publicado. Es
/// el mismo error que el texto legal viejo, del otro lado: decirle que está
/// oculto cuando está visible.
///
/// Devuelve un `AsyncValue`: mientras la fila 3 va a buscar el espejo, la
/// pantalla NO debe pintar "No publicada". Un "todavía no sé" mostrado como
/// "no" es exactamente la falla que este provider existe para arreglar.
final trainerLocationPublishedProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  final fields = ref.watch(
    userProfileProvider.select((async) {
      final p = async.valueOrNull;
      if (p == null) return null;
      return (
        uid: p.uid,
        consentAt: p.trainerLocationConsentAt,
        promptedAt: p.trainerLocationConsentPromptedAt,
      );
    }),
  );
  // Sin perfil no hay respuesta. La fila de estado sólo se pinta cuando el PF
  // tiene ubicaciones cargadas, así que en la práctica no se llega acá.
  if (fields == null) return false;

  // Filas 2 y 4 — otorgado.
  if (fields.consentAt != null) return true;
  // Fila 1 — nunca preguntado / legacy: sigue publicado por status quo.
  if (fields.promptedAt == null) return true;

  // Fila 3 — según el espejo. `revokeTrainerLocationConsent` sí lo vacía, así
  // que el revocado da false acá; el que cerró sin decidir, true.
  final espejo =
      await ref.watch(trainerPublicProfileRepositoryProvider).getById(
            fields.uid,
          );
  return espejo != null && espejo.trainerLocations.isNotEmpty;
});
