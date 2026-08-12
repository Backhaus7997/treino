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

/// Clave de [checkInByDateProvider]: dueño + fecha local `YYYY-MM-DD`.
typedef CheckInKey = ({String uid, String date});

/// Check-in ya registrado para [CheckInKey.date], o `null` si ese día está en
/// blanco.
///
/// Lo consume el resumen post-entreno para no pisar en silencio un registro
/// que ya existe: si el día ya tiene check-in, la pantalla lo muestra y el
/// sheet abre precargado en vez de arrancar vacío.
///
/// autoDispose: se re-lee al volver a montar la pantalla, sin invalidate
/// manual desde otros features.
final checkInByDateProvider =
    FutureProvider.autoDispose.family<CheckIn?, CheckInKey>((ref, key) async {
  if (key.uid.isEmpty || key.date.isEmpty) return null;
  return ref.read(checkInRepositoryProvider).getByDate(key.uid, key.date);
});

/// Escribe el check-in del día. Un solo método porque slice 1 sólo captura;
/// las lecturas agregadas (la curva de tendencia) son de su propio slice.
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
  /// [now] existe sólo para los tests: fija el reloj y, con él, la fecha local
  /// que va como id del documento. En producción se omite.
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
        date: checkInDateKey(clock),
        feeling: feeling,
        hasPain: hasPain,
        // Sin dolor no hay zonas: evita que un toggle de "sí" revertido a
        // "no" deje zonas huérfanas persistidas.
        painAreas: hasPain ? painAreas : const [],
        note: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
        recordedAt: clock.toUtc(),
        sessionId: sessionId,
      );

      await ref.read(checkInRepositoryProvider).save(uid, checkIn);
      ref.invalidate(
        checkInByDateProvider((uid: uid, date: checkIn.date)),
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
