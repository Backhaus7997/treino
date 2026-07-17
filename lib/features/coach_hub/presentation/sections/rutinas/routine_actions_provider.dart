// Mutación mínima de rutinas para el Coach Hub web (Fase 5, WU-04). Hoy
// sólo soporta archivar — la ÚNICA mutación cableada desde esta pantalla
// (`RoutineRepository.archive` ya existe; duplicar/asignar quedan fuera de
// scope hasta que haya algo real a lo que cablearlas).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart'
    show routineRepositoryProvider;

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
  /// [assignedRoutinesProvider] de [athleteId] para que la fila desaparezca
  /// de "Activas" en el próximo fetch.
  ///
  /// Devuelve `true` en éxito, `false` si el repo tira una excepción — la UI
  /// decide cómo comunicar el error (snackbar).
  Future<bool> archive({
    required String routineId,
    required String athleteId,
  }) async {
    try {
      await ref.read(routineRepositoryProvider).archive(routineId);
      ref.invalidate(assignedRoutinesProvider(athleteId));
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
