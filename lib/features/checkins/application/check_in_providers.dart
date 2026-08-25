import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../workout/domain/muscle_group.dart';
import '../data/check_in_repository.dart';
import '../domain/check_in.dart';

final checkInRepositoryProvider = Provider<CheckInRepository>(
  (ref) => CheckInRepository(firestore: ref.watch(firestoreProvider)),
);

/// Clave de [checkInsForDateProvider]: dueño + fecha local `YYYY-MM-DD`.
typedef CheckInKey = ({String uid, String date});

/// Check-ins registrados para [CheckInKey.date], del más viejo al más nuevo.
/// Lista vacía si ese día está en blanco.
///
/// Devuelve una LISTA y no un solo registro porque desde #643 el día ya no es
/// el id del documento: dos entrenos el mismo día dejan dos registros, y
/// quedarse con uno solo sería reintroducir por la puerta de atrás el
/// last-write-wins que la subcolección vino a arreglar.
///
/// Cada consumidor elige cuál le corresponde:
///
///  * el resumen post-sesión, el suyo — [checkInForSession];
///  * la tarjeta de Home, el último del día — [latestCheckIn].
///
/// autoDispose: se re-lee al volver a montar la pantalla, sin invalidate
/// manual desde otros features.
final checkInsForDateProvider = FutureProvider.autoDispose
    .family<List<CheckIn>, CheckInKey>((ref, key) async {
  if (key.uid.isEmpty || key.date.isEmpty) return const [];
  return ref.read(checkInRepositoryProvider).getForDate(key.uid, key.date);
});

/// El check-in que [sessionId] originó, o `null` si esa sesión todavía no
/// registró nada.
///
/// Es lo que hace que un SEGUNDO entreno del mismo día vuelva a ofrecer el
/// paso en vez de mostrar el registro del primero como si fuera suyo.
CheckIn? checkInForSession(List<CheckIn> dayCheckIns, String sessionId) {
  for (final c in dayCheckIns.reversed) {
    if (c.sessionId == sessionId) return c;
  }
  return null;
}

/// El registro más reciente del día, sin importar de dónde salió. `null` si el
/// día está en blanco.
CheckIn? latestCheckIn(List<CheckIn> dayCheckIns) =>
    dayCheckIns.isEmpty ? null : dayCheckIns.last;

/// Escribe el check-in del día — lo crea o edita uno existente.
class CheckInNotifier extends AutoDisposeAsyncNotifier<void> {
  /// Guard de reentrancia: el gate del botón depende de que la UI vea el
  /// [AsyncLoading] de abajo, y eso recién ocurre en el próximo frame — dos
  /// taps dentro de esa ventana escribirían dos veces. Mismo patrón que
  /// `PostWorkoutNotifier`.
  bool _saving = false;

  @override
  Future<void> build() async {}

  /// Registra cómo se sintió el usuario.
  ///
  /// [existing] decide entre crear y editar: si viene un registro ya
  /// persistido, se ACTUALIZA ese documento y se conserva SU fecha —
  /// [now] pasa a ser sólo la marca de la edición. Sin [existing] se crea uno
  /// nuevo, que NUNCA pisa a otro del mismo día: para eso el id dejó de ser la
  /// fecha.
  ///
  /// [now] existe sólo para los tests: fija el reloj y, con él, la fecha local
  /// de un registro nuevo. En producción se omite.
  ///
  /// Lanza si no hay usuario autenticado o si Firestore rechaza la escritura —
  /// el caller decide qué mostrar. Nunca traga el error: un registro que el
  /// usuario cree guardado y no se guardó es peor que un aviso de fallo.
  Future<void> submit({
    required CheckInFeeling feeling,
    bool hasPain = false,
    List<MuscleGroup> painAreas = const [],
    String? note,
    String? sessionId,
    CheckIn? existing,
    DateTime? now,
  }) async {
    if (_saving) return;
    _saving = true;
    state = const AsyncLoading();
    try {
      final uid = ref.read(currentUidProvider);
      if (uid == null || uid.isEmpty) {
        throw StateError('CheckInNotifier.submit sin usuario autenticado');
      }

      final clock = now ?? DateTime.now();
      final trimmed = note?.trim();
      final checkIn = CheckIn(
        // Editar no re-imputa el registro a otro día: la fecha del documento
        // es la del hecho, no la de la corrección.
        date: existing?.date ?? checkInDateKey(clock),
        feeling: feeling,
        hasPain: hasPain,
        // Sin dolor no hay zonas: evita que un toggle de "sí" revertido a
        // "no" deje zonas huérfanas persistidas.
        painAreas: hasPain ? painAreas : const [],
        note: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
        recordedAt: clock.toUtc(),
        sessionId: sessionId,
        id: existing?.id,
      );

      await ref.read(checkInRepositoryProvider).save(uid, checkIn);
      ref.invalidate(
        checkInsForDateProvider((uid: uid, date: checkIn.date)),
      );
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    } finally {
      // Se libera SIEMPRE, también al fallar: si no, un error dejaba el sheet
      // sin poder reintentar.
      _saving = false;
    }
  }
}

final checkInNotifierProvider =
    AsyncNotifierProvider.autoDispose<CheckInNotifier, void>(
  CheckInNotifier.new,
);
