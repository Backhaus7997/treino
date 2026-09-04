import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/legal/legal_content.dart';
import '../domain/user_role.dart';
import 'user_providers.dart';

/// consentimiento-legal-versionado — R4.
///
/// Descarte por sesión, uid-scoped, del aviso de política actualizada.
/// Mismo patrón que [TrainerLocationConsentDismissed]
/// (`trainer_location_consent_providers.dart`), y por la misma razón de
/// scoping: un segundo usuario que entra en el mismo dispositivo tiene que
/// recibir su propio aviso.
///
/// A diferencia del consentimiento del PF, acá NO hay campo persistido: el
/// aviso es informativo y no constituye evidencia de nada, así que no vale
/// un campo más en el perfil. El costo es conocido y asumido: vuelve a
/// aparecer en el próximo arranque en frío hasta que el usuario re-acepte.
/// Persistir el descarte es follow-up, no parte de este change.
class LegacyPrivacyNoticeDismissed extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(userProfileProvider.select((p) => p.valueOrNull?.uid));
    return false;
  }

  void markDismissed() => state = true;
}

final legacyPrivacyNoticeDismissedProvider =
    NotifierProvider<LegacyPrivacyNoticeDismissed, bool>(
  LegacyPrivacyNoticeDismissed.new,
);

/// Si al usuario le corresponde el aviso no bloqueante de política
/// actualizada.
///
/// **Por qué el gate es una FECHA y no `acceptedPrivacyVersion`.** Este
/// change no hace backfill, así que toda cuenta anterior tiene
/// `acceptedPrivacyVersion == null` — el campo no distingue a nadie hasta
/// que la población rote. La única evidencia que ya existe hoy en
/// producción es `termsAcceptedAt`, y por eso la comparación es contra
/// [kPrivacyV1PublishedAt].
///
/// **Por qué sólo atletas.** Al entrenador la sección "4. Ubicación" vieja
/// le decía algo FALSO, y su camino es el sheet de re-consentimiento, que
/// además le ofrece apagar la publicación. Al atleta el texto viejo le era
/// sustancialmente cierto: el nuevo agrega precisión (la zona de ~5 km que
/// se le manda al proveedor de mapas), no revela un tratamiento oculto.
/// Bloquear o interrogar a quien no fue inducido a error sería teatro.
///
/// **Por qué `termsAcceptedAt == null` NO recibe aviso.** Es la cuenta
/// legacy pre-QA-AUTH-001: no hay evidencia de qué aceptó ni cuándo.
/// Decirle "actualizamos la política que aceptaste" afirmaría un hecho que
/// no tenemos (AGENTS.md §11.1).
final shouldShowLegacyPrivacyNoticeProvider = Provider<bool>((ref) {
  if (ref.watch(legacyPrivacyNoticeDismissedProvider)) return false;

  // select() sobre los 2 campos relevantes — AGENTS.md §6. El record tiene
  // igualdad por valor: no re-emite en cada cambio del perfil completo.
  final fields = ref.watch(
    userProfileProvider.select((async) {
      final p = async.valueOrNull;
      if (p == null) return null;
      return (role: p.role, acceptedAt: p.termsAcceptedAt);
    }),
  );
  if (fields == null) return false;

  if (fields.role != UserRole.athlete) return false;
  final acceptedAt = fields.acceptedAt;
  if (acceptedAt == null) return false;
  return acceptedAt.isBefore(kPrivacyV1PublishedAt);
});
