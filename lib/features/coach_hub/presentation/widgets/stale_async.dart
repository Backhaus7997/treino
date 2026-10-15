import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `true` cuando el stream/future ya había entregado datos y DESPUÉS falló.
///
/// Riverpod 2.5+ preserva el último valor dentro del `AsyncError`
/// (`copyWithPrevious`), así que `hasValue` y `hasError` pueden ser `true` a la
/// vez. Las pantallas del Coach Hub priorizan el valor (no vacían lo que ya
/// mostraban), pero un stream de Firestore se CIERRA después de emitir un error:
/// casi siempre es permanente (permission-denied, vínculo revocado) y los datos
/// quedan congelados. Este getter es el disparador del `StaleDataNotice`.
///
/// Mientras se reintenta (`isLoading`) el aviso se esconde: el reintento está en
/// curso y, si vuelve a fallar, reaparece solo.
extension StaleAsyncValue<T> on AsyncValue<T> {
  bool get isStale => hasValue && hasError && !isLoading;
}
