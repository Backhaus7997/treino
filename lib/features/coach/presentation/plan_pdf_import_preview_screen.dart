import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/tokens/tokens.dart';
import '../../../core/moderation/moderation_guard.dart';
import '../../../core/widgets/motion/treino_fade_slide_in.dart';
import '../../../core/widgets/treino_confirm_dialog.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../core/widgets/treino_select.dart';
import '../../../core/widgets/treino_toast.dart';
import '../../../l10n/app_l10n.dart';
import '../../coach_hub/application/plan_import_preview_controller.dart';
import '../../coach_hub/application/plan_import_providers.dart';
import '../../coach_hub/data/exercise_matcher.dart';
import '../../coach_hub/data/plan_pdf_import_service.dart'
    show kPdfPlanNameMaxLength;
import '../../coach_hub/domain/periodized_plan.dart';
import '../../coach_hub/presentation/widgets/create_custom_exercise_dialog.dart';
import '../../coach_hub/presentation/widgets/import_plan_widgets.dart';
import '../../coach_hub/presentation/widgets/periodized_plan_preview.dart';
import '../../profile/domain/experience_level.dart';
import '../../workout/application/exercise_providers.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import 'custom_exercise_limit_gate.dart';
import 'plan_pdf_import_upload_screen.dart' show planPdfImportPath;
import 'widgets/exercise_picker_sheet.dart';

/// Ruta de la vista previa para [athleteId].
String planPdfImportPreviewPath(String athleteId) =>
    '${planPdfImportPath(athleteId)}/preview';

/// Vista previa de un plan importado de PDF, en mobile
/// (docs/plan-import-pdf.md, pasos 4 a 6): revisar, resolver los ejercicios
/// y asignar al alumno. No es un editor: después de asignar se ofrece abrir
/// el plan en el editor de siempre.
///
/// La orquestación es de [PlanImportPreviewController]; acá van los
/// diálogos, los avisos y la navegación.
class PlanPdfImportPreviewScreen extends ConsumerStatefulWidget {
  const PlanPdfImportPreviewScreen({super.key, required this.athleteId});

  final String athleteId;

  @override
  ConsumerState<PlanPdfImportPreviewScreen> createState() =>
      _PlanPdfImportPreviewScreenState();
}

class _PlanPdfImportPreviewScreenState
    extends ConsumerState<PlanPdfImportPreviewScreen> {
  int _week = 0;
  ExperienceLevel _level = ExperienceLevel.intermediate;
  bool _saving = false;
  bool _bulkRunning = false;

  /// El PF resolvió algo a mano: salir lo perdería.
  bool _touched = false;

  /// Lo último que salió mal, en la pantalla.
  String? _error;

  /// Prendida al irse por un éxito: limpiar el borrador dispara un rebuild
  /// sin plan, y la red de seguridad («sin borrador, volvé») no tiene que
  /// pisar esa navegación (mismo bug que la vista previa del Coach Hub).
  bool _leaving = false;

  /// Nombre de la rutina, editable. Arranca con el del borrador (el del
  /// archivo, saneado) y cada cambio vuelve al borrador con `withName`.
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  bool _nameSeeded = false;

  /// La moderación rechazó el nombre: se muestra en el campo, no abajo.
  String? _nameError;

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _onNameChanged(String value) {
    _controller.rename(value);
    setState(() {
      _touched = true;
      _nameError = null;
    });
  }

  PlanImportPreviewController get _controller =>
      ref.read(planImportPreviewControllerProvider);

  void _back() => context.canPop()
      ? context.pop()
      : context.go('/coach/athlete/${widget.athleteId}');

  Future<void> _handleBack() async {
    if (_touched) {
      final l10n = AppL10n.of(context);
      final leave = await showTreinoConfirmDialog(
        context,
        title: l10n.coachHubPreviewDiscardTitle,
        body: l10n.coachHubPreviewDiscardBody,
        confirmLabel: l10n.coachHubPreviewDiscardConfirm,
      );
      if (!leave || !mounted) return;
    }
    _leaving = true;
    _controller.clear();
    _back();
  }

  void _afterResolve(bool resolved) {
    if (!resolved || !mounted) return;
    setState(() {
      _touched = true;
      _error = null;
    });
  }

  Future<void> _pick(ExerciseKey key) async {
    final picked = await showExercisePicker(context, single: true);
    if (!mounted || picked == null || picked.isEmpty) return;
    final ex = picked.first;
    // Lo que no está en el catálogo es un propio del PF: sin alias.
    final catalog = ref.read(exercisesProvider).valueOrNull ?? const [];
    _afterResolve(_controller.resolve(
      key,
      MatcherExercise(id: ex.id, name: ex.name, muscleGroup: ex.muscleGroup),
      custom: !catalog.any((c) => c.id == ex.id),
    ));
  }

  Future<void> _createCustom(ExerciseKey key) async {
    final resolved = await _controller.createCustomFor(
      key,
      canCreate: () async =>
          await intentarCrearEjercicioPropio(context, ref) && mounted,
      openForm: (rawName, canSave) async {
        final created = await showCreateCustomExerciseDialog(
          context,
          initialName: rawName,
          canSave: () => mounted && canSave(),
        );
        return mounted ? created : null;
      },
    );
    _afterResolve(resolved);
  }

  void _useAlternative(ExerciseKey key) {
    final alternative = _controller.draft?.alternatives[key];
    if (alternative == null) return;
    _afterResolve(_controller.resolve(key, alternative));
  }

  Future<void> _createBulk() async {
    if (_bulkRunning) return;
    final l10n = AppL10n.of(context);
    setState(() {
      _bulkRunning = true;
      _error = null;
    });
    try {
      final check = await _controller.checkBulkCustom();
      if (!mounted) return;
      final int max;
      switch (check) {
        case BulkCustomQuotaUnknown():
          setState(() => _error = l10n.pdfImportBulkQuotaUnknown);
          return;
        case BulkCustomReady(:final allowed, :final total) when allowed == 0:
          // El mismo aviso de tope que el resto de la app.
          if (total > 0) await intentarCrearEjercicioPropio(context, ref);
          return;
        case BulkCustomReady(:final allowed, :final total) when allowed < total:
          final ok = await showTreinoConfirmDialog(
            context,
            title: l10n.pdfImportBulkPartialTitle(allowed, total),
            body: l10n.pdfImportBulkPartialBody,
            confirmLabel: l10n.pdfImportBulkCreate(allowed),
            destructive: false,
          );
          if (!ok || !mounted) return;
          max = allowed;
        case BulkCustomReady(:final total):
          max = total;
      }
      final result = await _controller.createCustomInBulk(max: max);
      if (!mounted) return;
      setState(() {
        if (result.created > 0) _touched = true;
        if (result.error != null) {
          _error = l10n.pdfImportBulkFailed(result.created, result.requested);
        }
      });
    } finally {
      if (mounted) setState(() => _bulkRunning = false);
    }
  }

  Future<void> _assign() async {
    final l10n = AppL10n.of(context);
    final draft = _controller.draft;
    final uid = ref.read(currentUidProvider);
    if (draft == null || uid == null || uid.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final outcome = await _controller.assign(
      athleteIds: [widget.athleteId],
      trainerUid: uid,
      routineName: _nameController.text,
      level: _level,
    );
    if (!mounted) return;
    switch (outcome) {
      case PlanAssignSuccess(:final routineIds):
        // Antes del await se capturan: después la pantalla ya no está.
        final messenger = ScaffoldMessenger.of(context);
        final router = GoRouter.of(context);
        final routineId = routineIds.isEmpty ? null : routineIds.first;
        _leaving = true;
        _controller.clear();
        _back();
        showTreinoToastOn(
          messenger,
          l10n.pdfImportAssigned,
          type: TreinoToastType.success,
          duration: const Duration(seconds: 8),
          action: routineId == null
              ? null
              : TreinoToastAction(
                  label: l10n.pdfImportOpenEditor,
                  onPressed: () => router.push(
                    '/workout/routine-editor/${widget.athleteId}',
                    extra: routineId,
                  ),
                ),
        );
        return;
      case PlanAssignModerationBlocked(:final campo) when campo == 'name':
        // El nombre es lo único que se corrige acá: el foco va al campo,
        // con el mensaje, y se reintenta sin volver a importar.
        _nameError = l10n.moderationBlockedMessage;
        _nameFocus.requestFocus();
      case PlanAssignModerationBlocked(:final campo):
        final where = ModerationGuard.ubicacionLegible(campo);
        _error = where == null
            ? l10n.moderationBlockedMessage
            : '$where: ${l10n.moderationBlockedMessage}';
      case PlanAssignBlockedUnresolved(:final pendingSuggestions):
        _error = l10n.pdfImportPending(
            _controller.draft?.unresolved.length ?? pendingSuggestions);
      case PlanAssignNoAthletes() ||
            PlanAssignAllFailed() ||
            PlanAssignPartial():
        _error = l10n.pdfImportAssignFailed;
    }
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final draft = ref.watch(periodizedImportProvider);

    if (draft == null) {
      // Entrada sin borrador (deep link, o se perdió): de vuelta a la ficha.
      if (!_leaving) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_leaving) _back();
        });
      }
      return Scaffold(backgroundColor: palette.bg);
    }

    if (!_nameSeeded) {
      _nameSeeded = true;
      _nameController.text = draft.name;
    }
    final plan = draft.plan;
    final week = _week.clamp(0, plan.numWeeks - 1);
    final days = plan.days.where((d) => d.rows.isNotEmpty).toList();
    final pending = draft.unresolved.length;
    final bulk = _controller.bulkCustomGroups.length;

    return PopScope(
      canPop: !_touched,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: palette.bg,
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.s20, AppSpacing.s12, AppSpacing.s20, AppSpacing.s20),
            child: ElevatedButton(
              key: const Key('pdf_import_assign'),
              onPressed:
                  pending > 0 || _saving || _bulkRunning ? null : _assign,
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: TreinoButtonTokens.foreground(context),
                disabledBackgroundColor: palette.border,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
              child: _saving
                  ? SizedBox.square(
                      dimension: AppSpacing.s20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: TreinoButtonTokens.foreground(context),
                      ),
                    )
                  : Text(
                      l10n.pdfImportAssign,
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: AppFonts.w700,
                        fontSize: AppTextSize.body,
                        letterSpacing: 0.8,
                      ),
                    ),
            ),
          ),
        ),
        body: AppBackground(
          child: SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.s20, AppSpacing.s8,
                  AppSpacing.s20, AppSpacing.s20),
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: Icon(TreinoIcon.back, color: palette.textPrimary),
                      tooltip: l10n.commonBack,
                      onPressed: _handleBack,
                    ),
                    Expanded(
                      child: Text(
                        l10n.pdfImportPreviewTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: AppFonts.w700,
                          fontSize: AppTextSize.title,
                          letterSpacing: AppFonts.headingTracking,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  l10n.pdfImportReadSummary(days.length, plan.numWeeks),
                  style: importText(palette.textMuted),
                ),
                const SizedBox(height: AppSpacing.s14),
                TextField(
                  key: const Key('pdf_import_name'),
                  controller: _nameController,
                  focusNode: _nameFocus,
                  enabled: !_saving,
                  maxLength: kPdfPlanNameMaxLength,
                  textCapitalization: TextCapitalization.sentences,
                  style: importText(palette.textPrimary,
                      size: AppTextSize.bodyLarge),
                  decoration: InputDecoration(
                    labelText: l10n.pdfImportNameLabel,
                    errorText: _nameError,
                    counterText: '',
                  ),
                  onChanged: _onNameChanged,
                ),
                const SizedBox(height: AppSpacing.s12),
                TreinoSelectField<ExperienceLevel>(
                  value: _level,
                  sheetTitle: l10n.pdfImportLevel,
                  options: [
                    for (final l in ExperienceLevel.values)
                      TreinoSelectOption(value: l, label: l.displayNameEs),
                  ],
                  onChanged: (l) => setState(() => _level = l),
                ),
                if (draft.warnings.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s14),
                  ImportCard(
                    padding: AppSpacing.s14,
                    child: ImportDiagnosticsList(diagnostics: draft.warnings),
                  ),
                ],
                if (pending > 0) ...[
                  const SizedBox(height: AppSpacing.s14),
                  Text(
                    l10n.pdfImportPending(pending),
                    key: const Key('pdf_import_pending'),
                    style: importText(palette.warning, weight: AppFonts.w600),
                  ),
                ],
                if (bulk > 0) ...[
                  const SizedBox(height: AppSpacing.s12),
                  OutlinedButton.icon(
                    key: const Key('pdf_import_bulk'),
                    onPressed: _bulkRunning || _saving ? null : _createBulk,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: palette.accent),
                      foregroundColor: palette.accentText,
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                    ),
                    icon: Icon(TreinoIcon.plus, color: palette.accent),
                    label: Text(
                      l10n.pdfImportBulkCreate(bulk),
                      style:
                          importText(palette.accentText, weight: AppFonts.w700),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.s12),
                  Text(
                    _error!,
                    key: const Key('pdf_import_preview_error'),
                    style:
                        importText(palette.dangerText, weight: AppFonts.w600),
                  ),
                ],
                if (plan.numWeeks > 1) ...[
                  const SizedBox(height: AppSpacing.s14),
                  PeriodizedWeekSelector(
                    numWeeks: plan.numWeeks,
                    selected: week,
                    onChanged: (w) => setState(() => _week = w),
                  ),
                ],
                for (final (i, d) in days.indexed)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.s14),
                    child: TreinoFadeSlideIn(
                      delay: AppMotion.stagger(i),
                      child: PeriodizedDayPreviewCard(
                        day: d,
                        week: week,
                        draft: draft,
                        onConfirmSuggestion: (key) =>
                            _afterResolve(_controller.confirmSuggestion(key)),
                        onPickManual: (key, _) => _pick(key),
                        onCreateCustom: (key, _) => _createCustom(key),
                        onUseAlternative: _useAlternative,
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
