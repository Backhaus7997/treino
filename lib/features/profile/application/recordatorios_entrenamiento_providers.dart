import 'package:flutter_riverpod/flutter_riverpod.dart';

// carve-out: profile/application may import auth/application for authStateChangesProvider.
// The inverse (auth importing profile) is forbidden. See design section 4 + REQ-PROF-063.
import '../../auth/application/auth_providers.dart';
import 'user_providers.dart';

/// ¿Acepta el atleta logueado los recordatorios diarios de entrenamiento?
///
/// Escucha `users/{uid}.notificationPrefs.recordatorios_entrenamiento.push`.
/// Ausente es `true`, igual que el servidor: sólo un `false` explícito frena el
/// push (ver `UserRepository.watchRecordatoriosEntrenamiento`).
///
/// Es el gemelo de `correosPromocionalesProvider` y hereda TODAS sus
/// decisiones, por los mismos motivos (están explicados allá, no se repiten):
///
///  - devuelve un **`AsyncValue<bool>` a propósito**, y la pantalla lo consume
///    con `tieneLecturaVigente` (extensión de
///    `correos_promocionales_providers.dart`, que es genérica sobre
///    `AsyncValue<bool>` pese al nombre), NO con `valueOrNull ?? true`: «todavía
///    no sé» no es «sí»;
///  - `autoDispose` y sin `keepAlive`: la pantalla vive un instante y el
///    listener de Firestore se cierra al salir;
///  - sólo se observa el uid, para que el listener se re-arme al cambiar de
///    cuenta y nunca por otro cambio del estado de auth (AGENTS.md §6).
///
/// Sin sesión no hay a quién preguntarle: el stream queda sin emitir y el
/// provider se queda en carga.
final recordatoriosEntrenamientoProvider =
    StreamProvider.autoDispose<bool>((ref) {
  final uid = ref.watch(
    authStateChangesProvider.select((auth) => auth.valueOrNull?.uid),
  );
  if (uid == null) return const Stream<bool>.empty();
  return ref.watch(userRepositoryProvider).watchRecordatoriosEntrenamiento(uid);
});
