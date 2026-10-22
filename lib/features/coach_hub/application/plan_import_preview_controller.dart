import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_service.dart';
import '../../../core/moderation/moderation_guard.dart';
import '../../profile/domain/experience_level.dart';
import '../../workout/application/custom_exercise_providers.dart';
import '../../workout/application/routine_providers.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../workout/domain/custom_exercise.dart';
import '../../workout/domain/routine.dart';
import '../../workout/domain/routine_source.dart';
import '../../workout/domain/routine_visibility.dart';
import '../data/exercise_matcher.dart';
import '../data/periodized_import_draft.dart';
import '../data/periodized_routine_mapper.dart';
import '../domain/periodized_plan.dart';
import 'cf_providers.dart';
import 'plan_import_providers.dart';

/// Resultado de [PlanImportPreviewController.assign]. La UI elige el texto;
/// el controller sólo dice qué pasó.
sealed class PlanAssignOutcome {
  const PlanAssignOutcome();
}

/// No se intentó: hay componentes sin resolver (#1455). [pendingSuggestions]
/// > 0 = hay sugerencias por confirmar; si no, hay filas sin candidato.
final class PlanAssignBlockedUnresolved extends PlanAssignOutcome {
  const PlanAssignBlockedUnresolved({required this.pendingSuggestions});
  final int pendingSuggestions;
}

/// No se intentó: no hay alumnos elegidos.
final class PlanAssignNoAthletes extends PlanAssignOutcome {
  const PlanAssignNoAthletes();
}

/// La moderación vetó el texto del plan. Es el MISMO plan para todos los
/// alumnos, así que bloquea a todos con el mismo [campo]: reintentar no sirve.
final class PlanAssignModerationBlocked extends PlanAssignOutcome {
  const PlanAssignModerationBlocked(this.campo);
  final String campo;
}

/// Fallaron todos: no se guardó nada.
final class PlanAssignAllFailed extends PlanAssignOutcome {
  const PlanAssignAllFailed();
}

/// Algunos sí y otros no. [failedAthleteIds] en el orden de entrada, para
/// reintentar sólo esos.
final class PlanAssignPartial extends PlanAssignOutcome {
  const PlanAssignPartial({
    required this.assigned,
    required this.failedAthleteIds,
  });
  final int assigned;
  final List<String> failedAthleteIds;
}

/// Se asignó a los [assigned] alumnos. El borrador NO se limpia acá: lo
/// limpia la UI con [PlanImportPreviewController.clear] cuando ya decidió a
/// dónde navegar (si no, la red de seguridad de la pantalla —«sin borrador,
/// volvé a subir»— le gana a la navegación del éxito).
final class PlanAssignSuccess extends PlanAssignOutcome {
  const PlanAssignSuccess(this.assigned);
  final int assigned;
}

typedef _Fallo = ({String athleteId, String? campoBloqueo});

/// Orquestación de la vista previa de un plan importado (Excel en el Coach
/// Hub, PDF en mobile): resolver componentes, confirmar sugerencias, crear
/// propios y asignar. Sin widgets: los diálogos, los avisos y la navegación
/// son de cada pantalla, que entra por callbacks o lee el resultado tipado.
///
/// El borrador vive en [periodizedImportProvider]: es lo que empuja la
/// pantalla de subida y lo que la vista previa dibuja.
class PlanImportPreviewController {
  PlanImportPreviewController(this._ref);

  final Ref _ref;

  /// Hay un «Crear como propio» en curso (quota, formulario o guardado).
  bool _creatingCustom = false;

  PeriodizedImportDraft? get draft => _ref.read(periodizedImportProvider);

  /// Sin borrador cuenta como resuelto: no hay nada que resolver.
  bool isResolved(ExerciseKey key) => draft?.isResolved(key) ?? true;

  /// Asigna [exercise] al componente [key]. Devuelve false si no había
  /// borrador o el componente ya estaba resuelto (un doble tap no vuelve a
  /// llamar a `addAlias`).
  ///
  /// Se resuelve por la clave EXACTA (día, fila, componente). Con [custom],
  /// el propio recién creado resuelve además los homónimos exactos sin
  /// candidato: son el mismo ejercicio repetido en el plan. Un propio NO
  /// registra alias: `addAlias` indexa contra el catálogo global.
  bool resolve(
    ExerciseKey key,
    MatcherExercise exercise, {
    bool custom = false,
  }) {
    final current = draft;
    if (current == null || current.isResolved(key)) return false;
    _ref.read(periodizedImportProvider.notifier).state = custom
        ? current.resolveWithSameName(key, exercise)
        : current.resolve(key, exercise);
    if (!custom) {
      // FIRE-AND-FORGET: see ADR-CXP-006
      unawaited(_addAlias(exercise.id, rawNameOf(current.plan, key)));
    }
    return true;
  }

  /// Confirma la sugerencia pendiente de [key]. Si la sugerencia es un propio
  /// del PF (entra al catálogo del matcher), no registra alias.
  bool confirmSuggestion(ExerciseKey key) {
    final suggestion = draft?.suggestions[key];
    if (suggestion == null) return false;
    final uid = _ref.read(currentUidProvider) ?? '';
    final isCustom = uid.isNotEmpty &&
        (_ref.read(customExercisesForTrainerStreamProvider(uid)).valueOrNull ??
                const <CustomExercise>[])
            .any((c) => c.id == suggestion.id);
    return resolve(key, suggestion, custom: isCustom);
  }

  /// «Crear como propio» para UNA fila. El propio se crea recién al confirmar
  /// el formulario, nunca al subir el archivo. [canCreate] es el embudo del
  /// tope del plan (muestra su propio aviso y devuelve false en el tope);
  /// [openForm] abre el formulario con el nombre del PF precargado y llama a
  /// `canSave` justo antes de guardar.
  ///
  /// Uno a la vez: un doble clic abría dos formularios y el segundo dejaba un
  /// propio huérfano que consume el tope.
  Future<bool> createCustomFor(
    ExerciseKey key, {
    required Future<bool> Function() canCreate,
    required Future<CustomExercise?> Function(
      String rawName,
      bool Function() canSave,
    ) openForm,
  }) async {
    if (_creatingCustom || isResolved(key)) return false;
    final rawName = rawNameOf(draft!.plan, key);
    _creatingCustom = true;
    try {
      if (!await canCreate()) return false;
      // Durante el await la fila pudo resolverse por otro camino.
      if (isResolved(key)) return false;
      final created = await openForm(rawName, () => !isResolved(key));
      if (created == null) return false;
      return resolve(
        key,
        MatcherExercise(
          id: created.id,
          name: created.name,
          muscleGroup: created.muscleGroup,
        ),
        custom: true,
      );
    } finally {
      _creatingCustom = false;
    }
  }

  /// Asigna el borrador a cada uno de [athleteIds], en paralelo.
  ///
  /// En paralelo y no en serie: `createAssigned` resuelve cuando el SERVIDOR
  /// confirma la escritura, y un `await` por alumno encadenaba una ida y
  /// vuelta de red por cada uno. Cada intento atrapa SU error, así se sabe
  /// cuál falló y se puede reintentar sólo ese.
  Future<PlanAssignOutcome> assign({
    required List<String> athleteIds,
    required String trainerUid,
    required String routineName,
    required ExperienceLevel level,
  }) async {
    final current = draft;
    if (current == null) return const PlanAssignAllFailed();
    // Bloquean (#1455): sugerencias sin confirmar y componentes sin match.
    // Las celdas de semana vacías NO bloquean: son un aviso.
    if (current.unresolved.isNotEmpty) {
      return PlanAssignBlockedUnresolved(
        pendingSuggestions: current.pendingSuggestions,
      );
    }
    if (athleteIds.isEmpty) return const PlanAssignNoAthletes();

    final repo = _ref.read(routineRepositoryProvider);
    final analytics = _ref.read(analyticsServiceProvider);

    Future<_Fallo?> intentar(String athleteId) async {
      final routine = buildAssignedRoutine(
        current,
        trainerUid: trainerUid,
        athleteId: athleteId,
        routineName: routineName,
        level: level,
      );
      try {
        // `plan_assigned` lo emite `createAssigned`; `routine_created` va
        // acá porque lleva un `source` que sólo conoce el llamador.
        await repo.createAssigned(routine);
        analytics.logRoutineCreated(
          source: RoutineCreationSource.trainerAssigned,
          daysCount: routine.days.length,
          weeksCount: routine.numWeeks,
        );
        return null;
      } on ModerationBlockedException catch (e) {
        return (athleteId: athleteId, campoBloqueo: e.campo);
      } catch (_) {
        return (athleteId: athleteId, campoBloqueo: null);
      }
    }

    final resultados = await Future.wait(athleteIds.map(intentar));
    final failed = resultados.whereType<_Fallo>().toList();

    final campo = failed
        .map((f) => f.campoBloqueo)
        .firstWhere((c) => c != null, orElse: () => null);
    if (campo != null) return PlanAssignModerationBlocked(campo);
    if (failed.length == athleteIds.length) return const PlanAssignAllFailed();
    if (failed.isNotEmpty) {
      return PlanAssignPartial(
        assigned: athleteIds.length - failed.length,
        failedAthleteIds: [for (final f in failed) f.athleteId],
      );
    }
    return PlanAssignSuccess(athleteIds.length);
  }

  /// Descarta el borrador (después de asignar, o al salir).
  void clear() => _ref.read(periodizedImportProvider.notifier).state = null;

  /// Fire-and-forget: registra el alias para que el próximo import matchee
  /// solo. Falla en silencio (ADR-CXP-009): `addAlias` exige App Check y
  /// desde mobile puede no andar; el plan se guarda igual.
  Future<void> _addAlias(String exerciseId, String rawName) async {
    try {
      await _ref
          .read(cloudFunctionsProvider)
          .httpsCallable('addAlias')
          .call(<String, dynamic>{'exerciseId': exerciseId, 'alias': rawName});
    } catch (e) {
      debugPrint('[addAlias] swallowed: $e');
    }
  }
}

final planImportPreviewControllerProvider =
    Provider<PlanImportPreviewController>(PlanImportPreviewController.new);

/// Nombre tal cual lo escribió el PF para el componente [key] (es lo que se
/// guarda como alias al confirmar). Vacío si la clave no está en el plan.
String rawNameOf(PeriodizedPlan plan, ExerciseKey key) {
  for (final day in plan.days) {
    if (day.dayNumber != key.dayNumber) continue;
    for (final row in day.rows) {
      if (row.position != key.row) continue;
      for (final ex in row.exercises) {
        if (ex.component == key.component) return ex.rawName;
      }
    }
  }
  return '';
}

/// La `Routine` que se le asigna a [athleteId], con la procedencia de toda
/// asignación del PF.
Routine buildAssignedRoutine(
  PeriodizedImportDraft draft, {
  required String trainerUid,
  required String athleteId,
  required String routineName,
  required ExperienceLevel level,
}) {
  final name = routineName.trim();
  final routine = mapPeriodizedPlanToRoutine(
    draft.plan,
    draft.assignments,
    routineId: '',
    routineName: name.isEmpty ? 'Plan importado' : name,
    level: level,
  );
  return routine.copyWith(
    split: 'Custom',
    source: RoutineSource.trainerAssigned,
    assignedBy: trainerUid,
    assignedTo: athleteId,
    visibility: RoutineVisibility.private,
  );
}
