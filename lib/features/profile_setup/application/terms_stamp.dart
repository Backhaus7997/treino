import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

import '../../auth/presentation/legal/legal_content.dart';

// Estampado de la evidencia de consentimiento legal. Lo comparten el alta de
// mobile (ProfileSetupNotifier) y el onboarding del Hub: dos copias
// divergirían en las versiones.

/// ¿Hay que estampar los términos en esta escritura?
///
/// Si [observedHasEvidence] dice que ya hay consentimiento, se confía (lo
/// estampó el registro por email). Si no, se confirma contra el SERVIDOR con
/// [acceptedAtFromServer] antes de decidir: la caché local puede tener una
/// versión vieja del doc sin `termsAcceptedAt`, y estampar sobre ella pisaría
/// la evidencia original con un timestamp posterior (hallazgo de Codex en
/// #1228). Si la consulta falla, la excepción se propaga: es preferible fallar
/// a registrar consentimiento sobre un dato que no se pudo confirmar.
Future<bool> needsTermsStamp({
  required bool observedHasEvidence,
  required Future<DateTime?> Function() acceptedAtFromServer,
}) async {
  if (observedHasEvidence) return false;
  return (await acceptedAtFromServer()) == null;
}

/// Los TRES campos de evidencia (consentimiento-legal-versionado, R3): el
/// timestamp junto a las versiones vigentes de términos y privacidad. Quien lo
/// use debe haber pasado antes por [needsTermsStamp]: NUNCA se pisa evidencia
/// existente.
Map<String, Object?> termsStampFields({DateTime? now}) => <String, Object?>{
      'termsAcceptedAt': Timestamp.fromDate((now ?? DateTime.now()).toUtc()),
      'acceptedTermsVersion': kTermsVersion,
      'acceptedPrivacyVersion': kPrivacyVersion,
    };
