import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/routine.dart';
import 'routine_providers.dart' show routineRepositoryProvider;

/// Returns all plans assigned to the given athlete uid by a trainer,
/// ordered newest first — EN VIVO.
///
/// Es un stream y no un `Future` de un solo disparo (#1698): lo que el PF hace
/// con los planes del alumno —asignar uno, editarlo, archivarlo, o el archivado
/// masivo de `cleanupAssignedPlansOnUnlink` al terminar el vínculo— tiene que
/// llegar a su app sin recargar. Con el `FutureProvider` anterior el plan nuevo
/// no aparecía y el archivado seguía siendo arrancable hasta el próximo
/// arranque en frío. Mismo patrón que `userCreatedRoutinesProvider`, su
/// hermano del lado de las rutinas propias.
///
/// Los consumidores que hacen `await ref.watch(...future)` (Home, la lista
/// unificada) se recomponen solos en cada emisión: el `.future` de un
/// `StreamProvider` avisa cuando llega un dato nuevo.
///
/// Returns an empty list immediately when [athleteId] is empty — avoids a
/// Firestore round-trip for unauthenticated or unresolved uid states.
///
/// `autoDispose` ensures the provider is cleaned up (and the Firestore
/// listener cancelled) when no widget is listening. `family` lets each
/// athleteId maintain its own cached stream.
///
/// REQ-COACH-PLANS-003, REQ-COACH-PLANS-004, SCENARIO-436, SCENARIO-437.
final assignedRoutinesProvider =
    StreamProvider.autoDispose.family<List<Routine>, String>(
  (ref, athleteId) {
    if (athleteId.isEmpty) return Stream.value(const []);
    return ref.watch(routineRepositoryProvider).watchAssignedTo(athleteId);
  },
);

/// Returns the plans one trainer assigned to one athlete, newest first.
///
/// Trainer reads need both ids in the Firestore query so security rules can
/// prove `assignedBy == request.auth.uid`. The record gives `.family`
/// structural equality and keeps each trainer/athlete pair in its own cache.
final assignedRoutinesByTrainerProvider = FutureProvider.autoDispose
    .family<List<Routine>, ({String trainerId, String athleteId})>(
  (ref, key) async {
    if (key.athleteId.isEmpty) return const [];

    // ⚠️  `trainerId` vacío NO es "este PF no tiene planes": es "todavía no sé
    // quién es el PF". `currentUidProvider` sale de un STREAM
    // (`authStateChangesProvider.valueOrNull`), así que es null hasta que ese
    // stream emite — en un hard reload del Hub web, los primeros frames caen
    // acá con la cadena vacía.
    //
    // Devolver `const []` los resolvía como AsyncData, o sea como un HECHO, y
    // `_PlanesSection` le mostraba «Todavía no le asignaste planes.» a un PF
    // que sí le asignó. Se autocorregía al emitir el stream, pero mientras
    // tanto afirmaba algo falso — AGENTS.md §11.1.
    //
    // Un future que no completa deja el provider en `loading`, que es lo único
    // cierto en ese instante: la UI muestra «Cargando…». Cuando el uid
    // resuelve, la clave del family CAMBIA y el provider nuevo hace el fetch
    // de verdad; éste queda huérfano y lo recoge el autoDispose.
    if (key.trainerId.isEmpty) return Completer<List<Routine>>().future;

    return ref.watch(routineRepositoryProvider).listAssignedToByTrainer(
          trainerId: key.trainerId,
          athleteId: key.athleteId,
        );
  },
);

/// TODAS las rutinas de las que un PF es autor: sus plantillas y los planes
/// que asignó, más nuevas primero.
///
/// Es la contracara de [assignedRoutinesProvider]: aquél parte del ALUMNO y
/// éste del AUTOR. La pantalla de Rutinas del Coach Hub listaba personas
/// justamente porque esta mirada no existía.
///
/// ⚠️  Misma guarda que [assignedRoutinesByTrainerProvider], y por la misma
/// razón: un `trainerId` VACÍO no significa «este PF no tiene rutinas», sino
/// «todavía no sé quién es el PF». `currentUidProvider` sale de un stream, así
/// que es null hasta que emite — en un hard reload del Hub, los primeros
/// frames caen acá con la cadena vacía.
///
/// Devolver `const []` los resolvería como `AsyncData`, o sea como un HECHO, y
/// la pantalla diría «todavía no creaste ninguna rutina» a un PF que tiene
/// veinte. Un future que no completa deja el provider en `loading`, que es lo
/// único cierto en ese instante (AGENTS.md §11.1).
final routinesAuthoredByProvider =
    FutureProvider.autoDispose.family<List<Routine>, String>(
  (ref, trainerId) async {
    if (trainerId.isEmpty) return Completer<List<Routine>>().future;
    return ref.watch(routineRepositoryProvider).listAuthoredBy(trainerId);
  },
);
