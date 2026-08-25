import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/exercise_feedback_repository.dart';
import '../domain/exercise_feedback.dart';

/// Providers del canal alumno → PF por ejercicio (#628).
///
/// Están en su propio archivo y no dentro de `session_providers.dart` por la
/// misma razón que el repositorio: `session_providers.dart` ya es el índice de
/// todo lo que cuelga del entreno, y esto tiene contrato de privacidad propio.

final exerciseFeedbackRepositoryProvider = Provider<ExerciseFeedbackRepository>(
  (ref) => ExerciseFeedbackRepository(firestore: ref.watch(firestoreProvider)),
);

/// Clave de familia: el par (dueño de la sesión, sesión).
///
/// El MISMO tipo sirve para el alumno mirando lo suyo y para el PF mirando lo
/// del alumno — el gate es de las reglas, no del cliente. Record de Strings
/// para tener igualdad estructural en la familia.
typedef ExerciseFeedbackKey = ({String uid, String sessionId});

/// Stream vivo de los reportes de una sesión.
///
/// autoDispose: cierra el listener de Firestore al salir del player. Es la
/// regla 6 de AGENTS.md y acá pesa doble, porque el player es la pantalla más
/// caliente de la app y esta es una suscripción por sesión abierta.
final sessionExerciseFeedbackProvider = StreamProvider.autoDispose
    .family<List<ExerciseFeedback>, ExerciseFeedbackKey>((ref, key) {
  if (key.uid.isEmpty || key.sessionId.isEmpty) {
    return Stream.value(const <ExerciseFeedback>[]);
  }
  return ref
      .watch(exerciseFeedbackRepositoryProvider)
      .watch(uid: key.uid, sessionId: key.sessionId);
});

/// Los reportes de UN ejercicio dentro de la sesión, derivados del stream de
/// arriba.
///
/// Existe para que la card del ejercicio watchee lo más chico posible: sin
/// esto, cada una de las N cards del player se rebuildearía ante cualquier
/// reporte de cualquier ejercicio. Se resuelve con `select` sobre el provider
/// padre, así el único listener de Firestore sigue siendo uno solo.
final exerciseFeedbackCountProvider = Provider.autoDispose
    .family<int, ({ExerciseFeedbackKey key, String exerciseId})>((ref, arg) {
  return ref.watch(
    sessionExerciseFeedbackProvider(arg.key).select(
      (async) =>
          async.valueOrNull
              ?.where((f) => f.exerciseId == arg.exerciseId)
              .length ??
          0,
    ),
  );
});

/// Lectura única de los reportes de la sesión de OTRO usuario, para las
/// superficies del PF (athlete detail mobile y Coach Hub web).
///
/// Es un [FutureProvider] y no un stream a propósito: el PF mira historial,
/// no está al lado del alumno mientras entrena. Un listener vivo por cada fila
/// expandida de la tabla sería caro y no compraría nada.
///
/// Devuelve `[]` sin tocar Firestore si falta cualquiera de las dos claves.
final coachSessionExerciseFeedbackProvider = FutureProvider.autoDispose
    .family<List<ExerciseFeedback>, ({String athleteUid, String sessionId})>(
        (ref, key) async {
  if (key.athleteUid.isEmpty || key.sessionId.isEmpty) {
    return const <ExerciseFeedback>[];
  }
  return ref.read(exerciseFeedbackRepositoryProvider).list(
        uid: key.athleteUid,
        sessionId: key.sessionId,
      );
});
