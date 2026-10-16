import 'package:treino/features/coach_hub/presentation/widgets/stale_async.dart';
import 'package:treino/features/coach_hub/presentation/widgets/stale_data_notice.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/features/coach_hub/presentation/widgets/skeleton/coach_hub_skeleton.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/analytics/analytics_service.dart';
import '../../../core/moderation/moderation_guard.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../coach/application/trainer_link_providers.dart';
import '../../coach/domain/trainer_link.dart';
import '../../coach/domain/trainer_link_status.dart';
import '../../profile/application/user_providers.dart';
import '../../profile/application/user_public_profile_providers.dart';
import '../../profile/domain/experience_level.dart';
import '../../workout/application/custom_exercise_providers.dart';
import '../../workout/application/exercise_filter.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../workout/domain/custom_exercise.dart';
import '../../workout/application/exercise_providers.dart';
import '../../workout/domain/exercise.dart';
import '../../workout/domain/muscle_group.dart';
import '../../workout/application/routine_providers.dart';
import '../../workout/domain/routine.dart';
import '../../workout/domain/routine_source.dart';
import '../../workout/domain/routine_visibility.dart';
import '../../coach/presentation/custom_exercise_limit_gate.dart';
import '../application/cf_providers.dart';
import '../application/plan_import_providers.dart';
import '../data/exercise_matcher.dart';
import '../data/periodized_import_draft.dart';
import '../data/periodized_routine_mapper.dart';
import '../domain/periodized_plan.dart';
import 'widgets/create_custom_exercise_dialog.dart';
import 'widgets/filter_chips/filter_chips.dart';
import 'widgets/import_plan_widgets.dart';
import 'widgets/periodized_plan_preview.dart';
import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';

/// Preview del plan importado. Muestra:
/// - Nombre / días / semanas / nivel
/// - Lista de ejercicios por día (con badge "Sin match" para los no
///   resueltos contra `exercises`)
/// - Selector de atleta (de los vínculos activos del PF)
/// - Botón "Asignar plan" → crea Routine + redirige a dashboard
class CoachHubPlanPreviewScreen extends ConsumerStatefulWidget {
  const CoachHubPlanPreviewScreen({super.key});

  @override
  ConsumerState<CoachHubPlanPreviewScreen> createState() =>
      _CoachHubPlanPreviewScreenState();
}

/// Resultado de intentar asignarle el plan importado a UN atleta, dentro del
/// batch en paralelo de [_CoachHubPlanPreviewScreenState._assign]. `null` en
/// el `Future.wait` sigue significando éxito — mismo criterio que antes de
/// este fix, que sólo guardaba el `athleteId` en el fallo.
///
/// Antes de esto el catch-all devolvía nada más que el id y perdía la
/// excepción real: un `ModerationBlockedException` (contenido vetado —
/// reintentar no sirve NUNCA, el mismo plan vuelve a fallar igual) se
/// mostraba con el mismo "Probá de nuevo" que un fallo de red (donde
/// reintentar sí puede andar). Mismo patrón que `ResultadoDePublicar` en
/// `routine_actions_provider.dart`: se preserva la categoría en el resultado
/// del batch en vez de aplanarla en el `catch`.
typedef _FalloAsignacion = ({String athleteId, String? campoBloqueo});

class _CoachHubPlanPreviewScreenState
    extends ConsumerState<CoachHubPlanPreviewScreen> {
  final Set<String> _selectedAthleteIds = <String>{};
  bool _saving = false;
  String? _error;

  /// Tracks whether the trainer has resolved any "sin match" exercise manually.
  /// Used to warn before leaving the preview, since the parsed+mapped plan lives
  /// in an ephemeral autoDispose provider and is lost on back-navigation.
  bool _hasManualMappings = false;

  /// Hay un «Crear como propio» en curso (quota, diálogo o guardado).
  bool _creatingCustom = false;

  /// Semana mostrada en las tarjetas de día (0-based).
  int _week = 0;

  /// Nivel de la rutina. La plantilla no lo trae: lo elige el PF.
  ExperienceLevel _level = ExperienceLevel.intermediate;

  late final TextEditingController _nameController = TextEditingController();
  bool _nameSeeded = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Se prende cuando la asignación salió bien y esta pantalla se está yendo
  /// al dashboard por decisión propia.
  ///
  /// Existe porque el éxito hace DOS cosas: limpia `periodizedImportProvider` y
  /// navega. Limpiarlo deja el plan en `null`, y `build` trata "plan null"
  /// como "alguien entró acá sin haber subido nada" y agenda un
  /// `go('/upload-plan')` en un post-frame. Esa red de seguridad le ganaba al
  /// `go('/dashboard')` del éxito: el PF asignaba, veía el cartel de que salió
  /// bien, y aterrizaba de nuevo en la pantalla de subir archivo.
  ///
  /// Medido con un test de un solo alumno contra el código anterior a la
  /// paralelización, así que no lo trajo ese cambio: estaba desde antes.
  bool _saliendoAlDashboard = false;

  /// Confirms before destroying the parsed (and possibly manually-mapped) plan
  /// by navigating back to the upload screen. Returns `true` if the trainer
  /// chose to leave, `false` (or null → treated as stay) otherwise.
  Future<bool> _confirmDiscard() async {
    final l10n = AppL10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final palette = AppPalette.of(ctx);
        return AlertDialog(
          backgroundColor: palette.bgCard,
          title: Text(
            l10n.coachHubPreviewDiscardTitle,
            style: TextStyle(color: palette.textPrimary),
          ),
          content: Text(
            l10n.coachHubPreviewDiscardBody,
            style: TextStyle(color: palette.textMuted, fontSize: 14),
          ),
          actions: [
            TreinoButton(
              label: l10n.commonCancel,
              variant: TreinoButtonVariant.ghost,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            const SizedBox(width: AppSpacing.s8),
            TreinoButton(
              label: l10n.coachHubPreviewDiscardConfirm,
              variant: TreinoButtonVariant.danger,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  /// Back handler shared by the header button and the system/hardware back.
  /// Skips the dialog when the trainer has not mapped anything manually
  /// (nothing valuable to lose beyond the re-parseable upload).
  Future<void> _handleBack() async {
    if (_hasManualMappings) {
      final leave = await _confirmDiscard();
      if (!leave) return;
    }
    if (!mounted) return;
    // pop back to the upload step (the push origin) so the picked file stays
    // in state; fall back to go() when there's no stack (deep-linked here).
    context.canPop() ? context.pop() : context.go('/upload-plan');
  }

  void _toggleAthlete(String athleteId) {
    setState(() {
      if (_selectedAthleteIds.contains(athleteId)) {
        _selectedAthleteIds.remove(athleteId);
      } else {
        _selectedAthleteIds.add(athleteId);
      }
      _error = null;
    });
  }

  Future<void> _assign(PeriodizedImportDraft draft, String trainerUid) async {
    // Bloquean la asignación (#1455): sugerencias sin confirmar y componentes
    // sin match. Las celdas de semana vacías NO bloquean: son un aviso.
    if (draft.unresolved.isNotEmpty) {
      setState(() => _error = draft.pendingSuggestions > 0
          ? 'Hay sugerencias pendientes. Confirmalas o cambialas antes de '
              'continuar.'
          : 'Hay ejercicios sin match. Vinculalos con la biblioteca o creá el propio antes de '
              'continuar.');
      return;
    }
    if (_selectedAthleteIds.isEmpty) {
      setState(() => _error = 'Elegí al menos un atleta antes de asignar.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final repo = ref.read(routineRepositoryProvider);
    final athleteIds = _selectedAthleteIds.toList();
    final analytics = ref.read(analyticsServiceProvider);

    // En PARALELO, no en serie.
    //
    // `createAssigned` termina en un `_collection.add(...)`, y ese future
    // resuelve cuando el SERVIDOR confirma la escritura — no cuando entra en
    // la caché local. Con un `for` y un `await` adentro, eso encadenaba una
    // ida y vuelta de red POR ALUMNO: asignarle el plan a cinco costaba cinco
    // esperas en fila cuando la red puede llevarlas juntas. Es el único lugar
    // de las cuatro superficies de asignación donde el costo se multiplica,
    // y por eso se arregla sin esperar la medición del resto: no hay número
    // que pueda justificar serializarlas.
    //
    // Cada future atrapa SU error y devuelve el id del alumno que falló, o
    // null si salió bien. `Future.wait` a secas aborta con el primer error y
    // se perdería tanto el resultado de los demás como el detalle de CUÁL
    // falló — que es justo lo que alimenta el reintento acotado de abajo.
    // `Future.wait` preserva el orden de entrada, así que `failed` sigue
    // saliendo en orden de selección, igual que con el loop.
    // Tipo de retorno EXPLICITO a propósito: sin él, Dart tiene que inferir
    // el tipo de la función a partir de tres `return` con formas distintas
    // (`null`, un record con `campoBloqueo: String`, uno con
    // `campoBloqueo: null`) y unificarlos de abajo hacia arriba. Anotado, cada
    // `return` se chequea CONTRA `_FalloAsignacion?` en vez de aportar a esa
    // inferencia — sin esto `campoBloqueo: null` podía terminar tipado `Null`
    // en vez de `String?` y romper la forma que espera `_FalloAsignacion`.
    Future<_FalloAsignacion?> intentarAsignar(String athleteId) async {
      final routine = _buildRoutine(
        draft: draft,
        trainerUid: trainerUid,
        athleteId: athleteId,
      );
      try {
        // `plan_assigned` ya NO va acá: lo emite `createAssigned`, que es
        // donde su dartdoc siempre dijo que estaba. `routine_created` sí se
        // queda — lleva un `source` que sólo conoce el llamador.
        await repo.createAssigned(routine);
        analytics.logRoutineCreated(
          source: RoutineCreationSource.trainerAssigned,
          daysCount: routine.days.length,
          weeksCount: routine.numWeeks,
        );
        return null;
      } on ModerationBlockedException catch (e) {
        // Rama propia y NO el catch-all de abajo: `_ensureRoutineTextIsClean`
        // (routine_repository.dart) corre sobre el MISMO `plan`
        // (name/split/summary/days) para los N atletas de este batch —
        // si el guard bloquea a uno los bloquea a TODOS, con el mismo
        // `campo`. Caer en el catch-all acá era justo el bug: mostraba
        // "Probá de nuevo" sobre un plan que va a fallar siempre, sin
        // ninguna guía de qué corregir.
        return (athleteId: athleteId, campoBloqueo: e.campo);
      } catch (_) {
        return (athleteId: athleteId, campoBloqueo: null);
      }
    }

    final resultados = await Future.wait(athleteIds.map(intentarAsignar));
    final failed = resultados.whereType<_FalloAsignacion>().toList();

    if (!mounted) return;

    // Bloqueo del filtro de términos vetados: por el determinismo de arriba,
    // si ALGUNO de los fallos trae `campoBloqueo` es porque TODOS los
    // atletas de este batch comparten el mismo plan bloqueado. No hay
    // subconjunto que reintentar -- "Probá de nuevo" es consejo falso acá -- y
    // un mensaje por atleta repetiría N veces lo mismo cuando es un plan
    // bloqueado, no N fallos independientes. `ubicacionLegible` le ahorra al
    // PF adivinar cuál de hasta 40 notas (5 días x 8 slots) fue.
    final campoBloqueado = failed
        .map((f) => f.campoBloqueo)
        .firstWhere((campo) => campo != null, orElse: () => null);
    if (campoBloqueado != null) {
      final l10n = AppL10n.of(context);
      final ubicacion = ModerationGuard.ubicacionLegible(campoBloqueado);
      setState(() {
        _error = ubicacion == null
            ? l10n.moderationBlockedMessage
            : '$ubicacion: ${l10n.moderationBlockedMessage}';
        _saving = false;
      });
      return;
    }

    // Total failure: nothing was saved. Keep the parsed plan and the current
    // selection so the trainer can retry without re-uploading the Excel.
    if (failed.length == athleteIds.length) {
      setState(() {
        _error = 'No pudimos guardar el plan. Probá de nuevo.';
        _saving = false;
      });
      return;
    }

    // Partial failure: some assignments succeeded, others didn't. Keep the
    // parsed plan in memory and stay on the preview, narrowing the selection
    // to only the failed athletes so the trainer can retry just those without
    // re-uploading and re-parsing the Excel.
    if (failed.isNotEmpty) {
      final ok = athleteIds.length - failed.length;
      setState(() {
        _selectedAthleteIds
          ..clear()
          ..addAll(failed.map((f) => f.athleteId));
        _error = 'Plan asignado a $ok atleta(s). ${failed.length} fallaron. '
            'Quedaron seleccionados para reintentar.';
        _saving = false;
      });
      return;
    }

    // Full success: clear the parsed plan and move on to the dashboard.
    // El orden importa menos que la bandera: limpiar el plan dispara el
    // rebuild con `plan == null`, y sin `_saliendoAlDashboard` la red de
    // seguridad de `build` nos manda a `/upload-plan` pisando este `go`.
    _saliendoAlDashboard = true;
    ref.read(periodizedImportProvider.notifier).state = null;
    final msg = athleteIds.length == 1
        ? 'Plan asignado correctamente.'
        : 'Plan asignado a ${athleteIds.length} atletas.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
    context.go('/dashboard');
  }

  /// Abre un modal con el catálogo de ejercicios para que el PF asigne
  /// manualmente uno de los componentes "sin match". Una vez elegido,
  /// actualiza el borrador del import con la asignación.
  Future<void> _pickExerciseFor({
    required ExerciseKey key,
    required String rowName,
  }) async {
    final exercises = await ref.read(exercisesProvider.future);
    if (!mounted) return;

    final picked = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.of(context).bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => _ExercisePickerSheet(
        rowName: rowName,
        exercises: exercises,
      ),
    );
    if (picked == null) return;

    _resolveExercise(
      key: key,
      rowName: rowName,
      exercise: MatcherExercise(
        id: picked.id,
        name: picked.name,
        muscleGroup: picked.muscleGroup,
      ),
    );
  }

  /// «Crear como propio»: el ejercicio propio se crea acá, al confirmar el
  /// formulario, NUNCA al subir el Excel. Mismo camino que el resto del Coach
  /// Hub: el embudo del tope del plan y el diálogo de ejercicio propio (con el
  /// texto original del PF precargado) sobre `CustomExerciseRepository`.
  Future<void> _createCustomFor({
    required ExerciseKey key,
    required String rowName,
  }) async {
    // Un solo «Crear como propio» a la vez: el doble clic abría dos diálogos y
    // el segundo guardado dejaba un ejercicio huérfano (la fila ya estaba
    // resuelta) que consume el tope del plan del PF.
    if (_creatingCustom) return;
    if (ref.read(periodizedImportProvider)?.isResolved(key) ?? true) return;
    _creatingCustom = true;
    try {
      // En el tope muestra el MISMO aviso que el resto de la app y corta: la
      // fila queda en rojo y «Vincular con la biblioteca» sigue disponible.
      final canCreate = await intentarCrearEjercicioPropio(context, ref);
      if (!canCreate || !mounted) return;
      // Durante el await de arriba la fila pudo resolverse por otro camino.
      if (_isResolvedNow(key)) return;
      final created = await showCreateCustomExerciseDialog(
        context,
        initialName: rowName,
        // Último control antes de que el diálogo llame al repo: si la pantalla
        // se desmontó o la fila ya está resuelta, no se crea nada.
        canSave: () => mounted && !_isResolvedNow(key),
      );
      if (created == null || !mounted) return;

      _resolveExercise(
        key: key,
        rowName: rowName,
        exercise: MatcherExercise(
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

  bool _isResolvedNow(ExerciseKey key) =>
      ref.read(periodizedImportProvider)?.isResolved(key) ?? true;

  void _confirmSuggestion({
    required ExerciseKey key,
    required String rowName,
  }) {
    final suggestion = ref.read(periodizedImportProvider)?.suggestions[key];
    if (suggestion == null) return;
    // La sugerencia puede ser un ejercicio PROPIO del PF (entra al catálogo del
    // matcher): no se registra alias, `addAlias` indexa sólo el global.
    final uid = ref.read(currentUidProvider) ?? '';
    final isCustom = uid.isNotEmpty &&
        (ref.read(customExercisesForTrainerStreamProvider(uid)).valueOrNull ??
                const <CustomExercise>[])
            .any((c) => c.id == suggestion.id);
    _resolveExercise(
      key: key,
      rowName: rowName,
      exercise: suggestion,
      custom: isCustom,
    );
  }

  void _resolveExercise({
    required ExerciseKey key,
    required String rowName,
    required MatcherExercise exercise,
    bool custom = false,
  }) {
    final current = ref.read(periodizedImportProvider);
    if (current == null) return;

    // Un componente ya resuelto no se resuelve dos veces: un doble tap llegaba
    // hasta acá y volvía a llamar a addAlias.
    if (current.isResolved(key)) return;

    // Se resuelve por la clave EXACTA (día, fila, componente): keyed por el
    // nombre solo se resolverían de una vez todos los renglones homónimos.
    // Un ejercicio propio recién creado además resuelve los homónimos EXACTOS
    // (mismo nombre normalizado): son el mismo ejercicio repetido en el plan.
    ref.read(periodizedImportProvider.notifier).state = custom
        ? current.resolveWithSameName(key, exercise)
        : current.resolve(key, exercise);
    setState(() {
      _error = null;
      _hasManualMappings = true;
    });
    // Un ejercicio propio NO se registra como alias: `addAlias` indexa contra
    // el catálogo global y el propio vive en `users/{uid}/customExercises`.
    if (custom) return;
    // FIRE-AND-FORGET: see ADR-CXP-006 // i18n: Fase 6 Etapa 5
    unawaited(_addAlias(exercise.id, rowName));
  }

  /// Fire-and-forget side effect: sends the manually mapped alias to
  /// the addAlias Cloud Function so future imports auto-match.
  ///
  /// Silent failure — any exception is swallowed and only logged via
  /// debugPrint. Never blocks or shows UI feedback. ADR-CXP-009.
  Future<void> _addAlias(String exerciseId, String rawName) async {
    try {
      await ref
          .read(cloudFunctionsProvider)
          .httpsCallable('addAlias')
          .call(<String, dynamic>{'exerciseId': exerciseId, 'alias': rawName});
    } catch (e) {
      debugPrint('[addAlias] swallowed: $e');
    }
  }

  Routine _buildRoutine({
    required PeriodizedImportDraft draft,
    required String trainerUid,
    required String athleteId,
  }) {
    final name = _nameController.text.trim();
    final routine = mapPeriodizedPlanToRoutine(
      draft.plan,
      draft.assignments,
      routineId: '',
      routineName: name.isEmpty ? 'Plan importado' : name,
      level: _level,
    );
    // Procedencia: igual que la asignación de siempre.
    return routine.copyWith(
      split: 'Custom',
      source: RoutineSource.trainerAssigned,
      assignedBy: trainerUid,
      assignedTo: athleteId,
      visibility: RoutineVisibility.private,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final draft = ref.watch(periodizedImportProvider);
    final profile = ref.watch(userProfileProvider).valueOrNull;

    if (draft == null) {
      // El `return` de abajo va SIEMPRE —sin plan no hay nada que dibujar—,
      // pero el rebote a subir archivo sólo si no nos estamos yendo solos.
      if (!_saliendoAlDashboard) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_saliendoAlDashboard) context.go('/upload-plan');
        });
      }
      return Scaffold(
        backgroundColor: palette.bg,
        body: Center(child: CircularProgressIndicator(color: palette.accent)),
      );
    }

    if (profile == null) {
      return Scaffold(
        backgroundColor: palette.bg,
        body: Center(child: CircularProgressIndicator(color: palette.accent)),
      );
    }

    if (!_nameSeeded) {
      _nameSeeded = true;
      _nameController.text = draft.name;
    }
    final plan = draft.plan;
    final week = _week.clamp(0, plan.numWeeks - 1);
    final days = plan.days.where((d) => d.rows.isNotEmpty).toList();

    return PopScope(
      // Block the implicit pop so manual mappings aren't silently lost; route
      // the system/hardware back through the same confirm flow as the header.
      canPop: !_hasManualMappings,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        backgroundColor: palette.bg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s20,
                  vertical: AppSpacing.s18,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                        palette: palette,
                        planName: _nameController.text.isEmpty
                            ? draft.name
                            : _nameController.text,
                        onBack: _handleBack),
                    const SizedBox(height: AppSpacing.s18),
                    _PlanMetaCard(
                      palette: palette,
                      daysCount: days.length,
                      numWeeks: plan.numWeeks,
                      nameController: _nameController,
                      level: _level,
                      onNameChanged: () => setState(() {}),
                      onLevelChanged: (l) => setState(() => _level = l),
                    ),
                    const SizedBox(height: AppSpacing.s18),
                    if (draft.unresolved.isNotEmpty) ...[
                      _UnmatchedWarning(palette: palette, draft: draft),
                      const SizedBox(height: AppSpacing.s18),
                    ],
                    if (draft.warnings.isNotEmpty) ...[
                      _WarningsCard(palette: palette, warnings: draft.warnings),
                      const SizedBox(height: AppSpacing.s18),
                    ],
                    if (plan.numWeeks > 1) ...[
                      PeriodizedWeekSelector(
                        numWeeks: plan.numWeeks,
                        selected: week,
                        onChanged: (w) => setState(() => _week = w),
                      ),
                      const SizedBox(height: AppSpacing.s14),
                    ],
                    for (final d in days)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.s14),
                        child: PeriodizedDayPreviewCard(
                          day: d,
                          week: week,
                          draft: draft,
                          onConfirmSuggestion: (key) {
                            final raw = _rawNameOf(plan, key);
                            _confirmSuggestion(key: key, rowName: raw);
                          },
                          onPickManual: (key, rawName) =>
                              _pickExerciseFor(key: key, rowName: rawName),
                          onCreateCustom: (key, rawName) =>
                              _createCustomFor(key: key, rowName: rawName),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.s8),
                    _AthletePicker(
                      palette: palette,
                      selectedAthleteIds: _selectedAthleteIds,
                      onToggle: _toggleAthlete,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.s14),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: importText(palette.dangerText,
                            size: AppTextSize.bodyDense),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.s18),
                    TreinoButton(
                      label: _selectedAthleteIds.length > 1
                          ? 'ASIGNAR PLAN A ${_selectedAthleteIds.length} ATLETAS'
                          : 'ASIGNAR PLAN',
                      expand: true,
                      loading: _saving,
                      onPressed: () => _assign(draft, profile.uid),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Nombre tal cual lo escribió el PF para el componente [key] (es lo que se
  /// guarda como alias al confirmar).
  static String _rawNameOf(PeriodizedPlan plan, ExerciseKey key) {
    for (final day in plan.days) {
      if (day.dayNumber != key.dayNumber) continue;
      for (final row in day.rows) {
        if (row.excelRow != key.row) continue;
        for (final ex in row.exercises) {
          if (ex.component == key.component) return ex.rawName;
        }
      }
    }
    return '';
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.palette,
    required this.planName,
    required this.onBack,
  });
  final AppPalette palette;
  final String planName;
  final Future<void> Function() onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TreinoIconButton(
          icon: TreinoIcon.arrowLeft,
          tooltip: 'Volver',
          color: palette.textPrimary,
          onPressed: onBack,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PREVIEW',
                style: GoogleFonts.barlowCondensed(
                  color: palette.highlight,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                planName.toUpperCase(),
                style: GoogleFonts.barlowCondensed(
                  color: palette.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  height: 1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlanMetaCard extends StatelessWidget {
  const _PlanMetaCard({
    required this.palette,
    required this.daysCount,
    required this.numWeeks,
    required this.nameController,
    required this.level,
    required this.onNameChanged,
    required this.onLevelChanged,
  });
  final AppPalette palette;
  final int daysCount;
  final int numWeeks;
  final TextEditingController nameController;
  final ExperienceLevel level;
  final VoidCallback onNameChanged;
  final ValueChanged<ExperienceLevel> onLevelChanged;

  @override
  Widget build(BuildContext context) {
    return ImportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: nameController,
            style: importText(palette.textPrimary, size: AppTextSize.bodyLarge),
            decoration: InputDecoration(
              labelText: 'Nombre de la rutina',
              labelStyle: importText(palette.textMuted),
            ),
            onChanged: (_) => onNameChanged(),
          ),
          const SizedBox(height: AppSpacing.s14),
          Wrap(
            spacing: AppSpacing.s20,
            runSpacing: AppSpacing.s12,
            children: [
              _MetaTile(
                palette: palette,
                label: 'Días/semana',
                value: '$daysCount',
              ),
              _MetaTile(
                palette: palette,
                label: 'Duración',
                value: '$numWeeks sem',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s14),
          Text(
            'NIVEL',
            style: TextStyle(
              fontFamily: AppFonts.barlowCondensed,
              color: palette.textMuted,
              fontSize: AppTextSize.caption,
              fontWeight: AppFonts.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          TreinoFilterChips(
            options: [for (final l in ExperienceLevel.values) l.displayNameEs],
            selected: {level.displayNameEs},
            onChanged: (next) {
              if (next.isEmpty) return;
              onLevelChanged(
                ExperienceLevel.values
                    .firstWhere((l) => l.displayNameEs == next.first),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MetaTile extends StatelessWidget {
  const _MetaTile({
    required this.palette,
    required this.label,
    required this.value,
  });
  final AppPalette palette;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.barlowCondensed(
            color: palette.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _UnmatchedWarning extends StatelessWidget {
  const _UnmatchedWarning({required this.palette, required this.draft});
  final AppPalette palette;
  final PeriodizedImportDraft draft;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final pendingSuggestions = draft.pendingSuggestions;
    final withoutSuggestion = draft.withoutSuggestion;
    final unresolved = pendingSuggestions + withoutSuggestion;
    return ImportCard(
      padding: AppSpacing.s14,
      borderColor: palette.warning,
      background: palette.warning.withValues(alpha: 0.12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            TreinoIcon.warning,
            color: palette.warning,
            semanticLabel: l10n.commonWarning,
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$unresolved ejercicio(s) por resolver',
                  style: importText(palette.textPrimary, weight: AppFonts.w700),
                ),
                const SizedBox(height: AppSpacing.hairline),
                Text(
                  '${pendingSuggestions > 0 ? '$pendingSuggestions con sugerencia pendiente. ' : ''}'
                  '${withoutSuggestion > 0 ? '$withoutSuggestion sin match. ' : ''}'
                  'No se puede asignar hasta que estén todos resueltos.',
                  style: importText(
                    palette.textMuted,
                    size: AppTextSize.bodyDense,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Avisos del parser, cada uno con su celda. No bloquean la asignación.
class _WarningsCard extends StatelessWidget {
  const _WarningsCard({required this.palette, required this.warnings});
  final AppPalette palette;
  final List<ImportDiagnostic> warnings;

  @override
  Widget build(BuildContext context) {
    return ImportCard(
      padding: AppSpacing.s14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            warnings.length == 1 ? '1 aviso' : '${warnings.length} avisos',
            style: importText(palette.textPrimary, weight: AppFonts.w700),
          ),
          const SizedBox(height: AppSpacing.s8),
          ImportDiagnosticsList(diagnostics: warnings),
        ],
      ),
    );
  }
}

/// Bottom sheet con search + lista del catálogo de exercises.
/// Devuelve el Exercise elegido (o null si el PF cancela).
class _ExercisePickerSheet extends StatefulWidget {
  const _ExercisePickerSheet({
    required this.rowName,
    required this.exercises,
  });
  final String rowName;
  final List<Exercise> exercises;

  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Same predicate as the catalog picker and the Coach Hub web dialog
  /// (tokenized, diacritic-tolerant, name + aliases). The old raw
  /// `muscleGroup` substring match is gone on purpose: it compared against
  /// the internal English key ('chest', …) that the Spanish UI never shows.
  List<Exercise> get _filtered {
    if (_query.trim().isEmpty) return widget.exercises;
    return widget.exercises
        .where((e) => exerciseMatchesFilters(
              e,
              query: _query,
              muscles: const {},
              equipment: const {},
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final filtered = _filtered;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (_, scrollController) => Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 18,
          bottom: MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Asignar a "${widget.rowName}"',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              autofocus: true,
              style: TextStyle(color: palette.textPrimary),
              decoration: InputDecoration(
                hintText: 'Buscar ejercicio…',
                hintStyle: TextStyle(color: palette.textMuted),
                prefixIcon: Icon(TreinoIcon.search, color: palette.textMuted),
                filled: true,
                fillColor: palette.bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: palette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: palette.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: palette.accent, width: 1.5),
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'Sin resultados.',
                        style: TextStyle(color: palette.textMuted),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: palette.border,
                      ),
                      itemBuilder: (_, i) {
                        final ex = filtered[i];
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          title: Text(
                            ex.name,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            muscleGroupLabel(ex.muscleGroup),
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 12,
                            ),
                          ),
                          onTap: () => Navigator.of(context).pop(ex),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AthletePicker extends ConsumerWidget {
  const _AthletePicker({
    required this.palette,
    required this.selectedAthleteIds,
    required this.onToggle,
  });
  final AppPalette palette;
  final Set<String> selectedAthleteIds;
  final void Function(String athleteId) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Real-time stream (not the deprecated one-shot FutureProvider) so a link
    // accepted/paused/terminated elsewhere updates the list live. ADR-CHLM-03.
    final linksAsync = ref.watch(trainerLinksStreamProvider);
    final displayLinksAsync = linksAsync.hasValue
        ? AsyncValue.data(linksAsync.requireValue)
        : linksAsync;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        staleNoticeIf(
          linksAsync.isStale,
          () => ref.invalidate(trainerLinksStreamProvider),
        ),
        _athleteOptions(displayLinksAsync),
      ],
    );
  }

  Widget _athleteOptions(AsyncValue<List<TrainerLink>> displayLinksAsync) {
    return displayLinksAsync.when(
      // Skeleton y no spinner: lo que viene es una LISTA de alumnos y su forma
      // ya la conocemos. El spinner medía 36px y la lista mide varios cientos,
      // así que al llegar los datos el bloque saltaba.
      loading: () => const CoachHubSkeleton(filas: 3),
      error: (_, __) => Text(
        'No pudimos cargar tus alumnos.',
        style: TextStyle(color: palette.textMuted),
      ),
      data: (links) {
        final active =
            links.where((l) => l.status == TrainerLinkStatus.active).toList();
        if (active.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palette.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.border),
            ),
            child: Text(
              'No tenés alumnos activos para asignarles este plan. '
              'Esperá que un atleta acepte tu vínculo y volvé a importar.',
              style: TextStyle(color: palette.textMuted, fontSize: 13),
            ),
          );
        }
        final count = selectedAthleteIds.length;
        final label = count == 0
            ? 'ASIGNAR A (ELEGÍ UNO O MÁS)'
            : 'ASIGNAR A · $count seleccionado(s)';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              style: GoogleFonts.barlowCondensed(
                color: palette.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            ...active.map(
              (link) => _AthleteOption(
                palette: palette,
                link: link,
                selected: selectedAthleteIds.contains(link.athleteId),
                onTap: () => onToggle(link.athleteId),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AthleteOption extends ConsumerWidget {
  const _AthleteOption({
    required this.palette,
    required this.link,
    required this.selected,
    required this.onTap,
  });
  final AppPalette palette;
  final TrainerLink link;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pubAsync = ref.watch(userPublicProfileProvider(link.athleteId));
    final name = pubAsync.valueOrNull?.displayName ?? 'Atleta';

    return MergeSemantics(
      child: Semantics(
        button: true,
        toggled: selected,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? palette.accent.withValues(alpha: 0.12)
                  : palette.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? palette.accent : palette.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Icon(
                    selected
                        ? TreinoIcon.checkCircleFill
                        : TreinoIcon.checkCircleEmpty,
                    color: selected ? palette.accent : palette.textMuted,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
