// Mutaciones de rutinas para el Coach Hub web: archivar y ELIMINAR.
//
// Las dos invalidan `routinesAuthoredByProvider`, que es de donde lee la
// pantalla de Rutinas desde que pasó a listar rutinas en vez de alumnos.
// Duplicar/asignar siguen fuera de scope.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart'
    show invalidateRoutineById, routineRepositoryProvider;

/// Notifier sin estado propio relevante para la UI: la fila que dispara la
/// acción mantiene su propio flag de "busy" local (mismo criterio que el
/// resto del Coach Hub web, ver `alumnos_screen.dart._confirmAction` +
/// llamada posterior). Este provider sólo centraliza la llamada al repo + la
/// invalidación del listado afectado, para que sea testeable sin montar
/// widgets.
class RoutineActionsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Archiva [routineId] (soft-delete, ADR-USR-04) e invalida
  /// [assignedRoutinesByTrainerProvider] del par [trainerId]/[athleteId] para
  /// que la fila desaparezca de "Activas" en el próximo fetch, más las cachés
  /// single-doc de la rutina vía [invalidateRoutineById].
  ///
  /// ⚠️  [trainerId] NO es decorativo: es parte de la CLAVE del provider. El
  /// listado del Coach Hub se mudó a `assignedRoutinesByTrainerProvider`
  /// porque el `list` del PF necesita `assignedBy` en la query para que las
  /// reglas lo puedan probar. Si esta invalidación siguiera pegándole a
  /// `assignedRoutinesProvider(athleteId)` —la clave VIEJA— la llamada no
  /// fallaría ni compilaría mal: simplemente invalidaría un provider que ya
  /// nadie mira, y la rutina archivada seguiría en pantalla hasta recargar.
  /// Un fallo silencioso, que es justo lo que AGENTS.md §11.1 prohíbe.
  ///
  /// Devuelve `true` en éxito, `false` si el repo tira una excepción — la UI
  /// decide cómo comunicar el error (snackbar).
  Future<bool> archive({
    required String routineId,
    required String trainerId,
    required String athleteId,
  }) async {
    try {
      await ref.read(routineRepositoryProvider).archive(routineId);
      ref.invalidate(assignedRoutinesByTrainerProvider(
        (trainerId: trainerId, athleteId: athleteId),
      ));
      // Y la grilla de la sección Rutinas, que lee de OTRO provider desde que
      // el eje pasó a ser el autor. Sin esta línea la card archivada seguiría
      // en pantalla hasta recargar — el mismo fallo silencioso que describe la
      // advertencia de arriba, una mudanza de provider más tarde.
      ref.invalidate(routinesAuthoredByProvider(trainerId));
      // El listado no alcanza: los lectores one-shot de la rutina archivada
      // (`routineByIdProvider` / `visibleRoutineByIdProvider`) siguen
      // devolviendo el doc con `status: active` hasta que se reinicie el
      // proceso. `ref.container` porque el notifier no es un widget.
      invalidateRoutineById(ref.container, routineId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// BORRA [routineId] de verdad. Irreversible.
  ///
  /// Convive con [archive] a propósito, no la reemplaza. La app archiva por
  /// defecto —«el documento se conserva para mantener referencias históricas
  /// de sesiones», ADR-USR-04— y eso sigue siendo lo correcto para un plan que
  /// alguien entrenó: las sesiones apuntan al doc, y borrarlo las deja sin
  /// referencia.
  ///
  /// Eliminar es para lo otro: una plantilla que nunca se entrenó, o un plan
  /// que se cargó mal y no debería figurar en la biblioteca. Quién ofrece cuál
  /// —y con qué advertencia— lo decide la UI, que es la que sabe si la rutina
  /// tiene alumno.
  ///
  /// Las reglas de Firestore ya restringen el borrado al dueño
  /// (`assignedBy == request.auth.uid`); esto no afloja nada.
  Future<bool> delete({
    required String routineId,
    required String trainerId,
  }) async {
    try {
      await ref.read(routineRepositoryProvider).deleteRoutine(routineId);
      ref.invalidate(routinesAuthoredByProvider(trainerId));
      invalidateRoutineById(ref.container, routineId);
      return true;
    } catch (_) {
      return false;
    }
  }
}

final routineActionsProvider =
    AsyncNotifierProvider<RoutineActionsNotifier, void>(
  RoutineActionsNotifier.new,
);
