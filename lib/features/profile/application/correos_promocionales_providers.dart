import 'package:flutter_riverpod/flutter_riverpod.dart';

// carve-out: profile/application may import auth/application for authStateChangesProvider.
// The inverse (auth importing profile) is forbidden. See design section 4 + REQ-PROF-063.
import '../../auth/application/auth_providers.dart';
import 'user_providers.dart';

/// ¿Acepta correos promocionales el usuario logueado?
///
/// Escucha `users/{uid}.notificationPrefs.novedades_plan.email`. Ausente es
/// `true`, igual que el servidor: sólo un `false` explícito frena el envío
/// (ver `UserRepository.watchCorreosPromocionales`).
///
/// Devuelve un **`AsyncValue<bool>` a propósito**, y la pantalla lo consume con
/// [CorreosPromocionalesLectura.tieneLecturaVigente], NO con `valueOrNull ??
/// true`. Ese atajo colapsa «todavía no sé» con «sí»: durante la carga el
/// interruptor se vería PRENDIDO, y un usuario que lo apagara en esa ventana
/// estaría confirmando un valor que nunca leyó. Mientras no hay respuesta
/// —cargando o con error— el interruptor va deshabilitado: «no sé» no es «sí».
///
/// **`hasValue` solo tampoco alcanza.** Riverpod conserva el valor anterior
/// cuando el estado pasa a carga o a error (`copyWithPrevious`): si el stream
/// falla después de una lectura buena, o si cambia el uid y el provider se
/// recalcula, `hasValue` sigue en `true` con el valor del documento VIEJO. Un
/// interruptor habilitado sobre eso deja tocar —y escribir sobre el uid nuevo—
/// una elección que el usuario hizo mirando otra cosa.
///
/// Sin sesión no hay a quién preguntarle: el stream queda sin emitir y el
/// provider se queda en carga, que para la pantalla es lo mismo que «no sé».
///
/// `autoDispose` y sin `keepAlive`: la pantalla vive un instante y el listener
/// de Firestore tiene que cerrarse al salir. Un provider eterno con un stream
/// de documento es además un `Timer`/listener vivo que se cuela en tests ajenos.
final correosPromocionalesProvider = StreamProvider.autoDispose<bool>((ref) {
  // Sólo el uid: el listener se re-arma al cambiar de cuenta y nunca por otro
  // cambio del estado de auth (AGENTS.md §6, `select` lo más chico posible).
  final uid = ref.watch(
    authStateChangesProvider.select((auth) => auth.valueOrNull?.uid),
  );
  if (uid == null) return const Stream<bool>.empty();
  return ref.watch(userRepositoryProvider).watchCorreosPromocionales(uid);
});

/// ¿Hay una respuesta vigente para el uid de ahora?
extension CorreosPromocionalesLectura on AsyncValue<bool> {
  /// `true` sólo si el estado es un dato firme: hay valor, NO se está
  /// recargando y NO hay un error encima.
  ///
  /// Las tres condiciones hacen falta porque `hasValue` también es `true` en un
  /// `AsyncLoading` o un `AsyncError` que arrastran el valor anterior (ver el
  /// dartdoc de [correosPromocionalesProvider]). Con sólo `hasValue`, después
  /// de una lectura buena el switch seguiría habilitado y mostrando el valor
  /// viejo ante un error del stream o un cambio de cuenta.
  bool get tieneLecturaVigente => hasValue && !isLoading && !hasError;
}
