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
import '../../../core/moderation/moderation_guard.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../coach/application/trainer_link_providers.dart';
import '../../coach/domain/trainer_link.dart';
import '../../coach/domain/trainer_link_status.dart';
import '../../profile/application/user_providers.dart';
import '../../profile/application/user_public_profile_providers.dart';
import '../../profile/domain/experience_level.dart';
import '../../workout/application/exercise_filter.dart';
import '../../workout/application/exercise_providers.dart';
import '../../workout/domain/exercise.dart';
import '../../workout/domain/muscle_group.dart';
import '../../coach/presentation/custom_exercise_limit_gate.dart';
import '../application/plan_import_preview_controller.dart';
import '../application/plan_import_providers.dart';
import '../data/exercise_matcher.dart';
import '../data/periodized_import_draft.dart';
import '../domain/periodized_plan.dart';
import 'widgets/create_custom_exercise_dialog.dart';
import 'widgets/filter_chips/filter_chips.dart';
import 'widgets/import_plan_widgets.dart';
import 'widgets/periodized_plan_preview.dart';
import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';
import 'package:treino/core/widgets/treino_toast.dart';

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

class _CoachHubPlanPreviewScreenState
    extends ConsumerState<CoachHubPlanPreviewScreen> {
  final Set<String> _selectedAthleteIds = <String>{};
  bool _saving = false;
  String? _error;

  /// Tracks whether the trainer has resolved any "sin match" exercise manually.
  /// Used to warn before leaving the preview, since the parsed+mapped plan lives
  /// in an ephemeral autoDispose provider and is lost on back-navigation.
  bool _hasManualMappings = false;

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

  Future<void> _assign(String trainerUid) async {
    final controller = ref.read(planImportPreviewControllerProvider);
    final pending = controller.draft;
    // Los bloqueos previos no prenden el spinner: se contestan en el acto.
    if (pending != null &&
        pending.unresolved.isEmpty &&
        _selectedAthleteIds.isNotEmpty) {
      setState(() {
        _saving = true;
        _error = null;
      });
    }

    final athleteIds = _selectedAthleteIds.toList();
    final outcome = await controller.assign(
      athleteIds: athleteIds,
      trainerUid: trainerUid,
      routineName: _nameController.text,
      level: _level,
    );
    if (!mounted) return;

    switch (outcome) {
      case PlanAssignBlockedUnresolved(:final pendingSuggestions):
        setState(() => _error = pendingSuggestions > 0
            ? 'Hay sugerencias pendientes. Confirmalas o cambialas antes de '
                'continuar.'
            : 'Hay ejercicios sin match. Vinculalos con la biblioteca o creá el propio antes de '
                'continuar.');
      case PlanAssignNoAthletes():
        setState(() => _error = 'Elegí al menos un atleta antes de asignar.');
      case PlanAssignModerationBlocked(:final campo):
        // El mismo plan para todos los atletas: si lo vetó para uno, lo vetó
        // para todos. «Probá de nuevo» sería consejo falso; la ubicación le
        // ahorra al PF adivinar cuál de hasta 40 notas fue.
        final l10n = AppL10n.of(context);
        final ubicacion = ModerationGuard.ubicacionLegible(campo);
        setState(() {
          _error = ubicacion == null
              ? l10n.moderationBlockedMessage
              : '$ubicacion: ${l10n.moderationBlockedMessage}';
          _saving = false;
        });
      case PlanAssignAllFailed():
        // No se guardó nada: se conserva el plan y la selección para
        // reintentar sin volver a subir el Excel.
        setState(() {
          _error = 'No pudimos guardar el plan. Probá de nuevo.';
          _saving = false;
        });
      case PlanAssignPartial(:final assigned, :final failedAthleteIds):
        // Quedan seleccionados sólo los que fallaron, para reintentar esos.
        setState(() {
          _selectedAthleteIds
            ..clear()
            ..addAll(failedAthleteIds);
          _error = 'Plan asignado a $assigned atleta(s). '
              '${failedAthleteIds.length} fallaron. '
              'Quedaron seleccionados para reintentar.';
          _saving = false;
        });
      case PlanAssignSuccess(:final assigned):
        // La bandera va ANTES de limpiar: limpiar el plan dispara el rebuild
        // con `plan == null`, y sin `_saliendoAlDashboard` la red de
        // seguridad de `build` nos manda a `/upload-plan` pisando este `go`.
        _saliendoAlDashboard = true;
        controller.clear();
        final msg = assigned == 1
            ? 'Plan asignado correctamente.'
            : 'Plan asignado a $assigned atletas.';
        showTreinoToast(
          context,
          msg,
          type: TreinoToastType.success,
        );
        context.go('/dashboard');
    }
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

    _afterResolve(ref.read(planImportPreviewControllerProvider).resolve(
          key,
          MatcherExercise(
            id: picked.id,
            name: picked.name,
            muscleGroup: picked.muscleGroup,
          ),
        ));
  }

  /// «Crear como propio»: el ejercicio propio se crea al confirmar el
  /// formulario, NUNCA al subir el Excel. La orquestación (uno a la vez,
  /// re-chequear que la fila siga sin resolver) es del controller; acá van el
  /// embudo del tope del plan y el diálogo de ejercicio propio del Coach Hub.
  Future<void> _createCustomFor({required ExerciseKey key}) async {
    final resolved =
        await ref.read(planImportPreviewControllerProvider).createCustomFor(
              key,
              // En el tope muestra el MISMO aviso que el resto de la app y
              // corta: la fila queda en rojo y «Vincular con la biblioteca»
              // sigue disponible.
              canCreate: () async =>
                  await intentarCrearEjercicioPropio(context, ref) && mounted,
              openForm: (rawName, canSave) async {
                final created = await showCreateCustomExerciseDialog(
                  context,
                  initialName: rawName,
                  // Último control antes de que el diálogo llame al repo: si
                  // la pantalla se desmontó o la fila ya está resuelta, no se
                  // crea nada.
                  canSave: () => mounted && canSave(),
                );
                return mounted ? created : null;
              },
            );
    _afterResolve(resolved);
  }

  void _confirmSuggestion(ExerciseKey key) => _afterResolve(
      ref.read(planImportPreviewControllerProvider).confirmSuggestion(key));

  /// Lo que la pantalla hace cuando el controller resolvió un componente.
  void _afterResolve(bool resolved) {
    if (!resolved || !mounted) return;
    setState(() {
      _error = null;
      _hasManualMappings = true;
    });
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
                          onConfirmSuggestion: _confirmSuggestion,
                          onPickManual: (key, rawName) =>
                              _pickExerciseFor(key: key, rowName: rawName),
                          onCreateCustom: (key, _) =>
                              _createCustomFor(key: key),
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
                      onPressed: () => _assign(profile.uid),
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
