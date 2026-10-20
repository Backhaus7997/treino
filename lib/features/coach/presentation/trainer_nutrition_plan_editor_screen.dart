import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/tokens/tokens.dart';
import '../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../core/widgets/treino_confirm_dialog.dart';
import '../../../core/widgets/treino_toast.dart';
import '../../../core/widgets/motion/treino_tappable.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../profile/application/user_public_profile_providers.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../application/nutrition_plan_providers.dart';
import '../domain/nutrition_plan.dart';
import '../domain/nutrition_plan_ids.dart';
import '../domain/nutrition_plan_presets.dart';

// Pie fijo con GUARDAR PLAN. Vive dentro del body: el `Scaffold` no lo
// conoce, así que un aviso con el editor abierto le taparía el botón. Su alto
// va en `bottomOffset` (mismo caso que `_kAltoDelPieFijo` del editor web).
const double _kPieArriba = 12;
const double _kPieAbajo = 20;
const double _kAltoBoton = 48;
const double _kAltoDelPie = _kPieArriba + _kAltoBoton + _kPieAbajo;

/// Editor mobile del plan nutricional de un alumno, para el PF (#1538).
///
/// Hasta acá el plan sólo se podía cargar desde el Coach Hub web, y el alumno
/// veía «Tu PF todavía no cargó tu plan nutricional» aunque su PF trabajara
/// todo desde el teléfono.
///
/// Mismo modelo, repositorio, presets y `sanitizeForSave` que el editor web —
/// lo que se guarda acá se ve igual allá y en la vista del alumno— pero con
/// una UI propia: los cuatro campos de una opción no entran en una fila de
/// 375 px, así que la opción se lee como fila y se edita en un bottom sheet.
///
/// Comportamiento:
/// - Sin plan guardado arranca de `defaultPresetMeals()`, como en web.
/// - Los cambios viven en un borrador local y se persisten todos juntos con
///   GUARDAR PLAN. Salir con cambios pendientes pide confirmación.
/// - Si la lectura falla NO arranca de los presets: guardar ese borrador
///   pisaría un plan que existe y no se pudo leer. Muestra el error y deja
///   reintentar.
class TrainerNutritionPlanEditorScreen extends ConsumerStatefulWidget {
  const TrainerNutritionPlanEditorScreen({super.key, required this.athleteId});

  final String athleteId;

  @override
  ConsumerState<TrainerNutritionPlanEditorScreen> createState() =>
      _TrainerNutritionPlanEditorScreenState();
}

class _TrainerNutritionPlanEditorScreenState
    extends ConsumerState<TrainerNutritionPlanEditorScreen> {
  /// Lo que el PF está editando.
  NutritionPlan? _draft;

  /// Contra qué se mide si hay cambios sin guardar: el plan tal como se leyó
  /// (o los presets, si no había plan), y después de guardar, lo guardado.
  NutritionPlan? _baseline;

  bool _saving = false;

  bool get _dirty => _draft != null && _draft != _baseline;

  void _seedIfNeeded(NutritionPlan? persisted, String trainerUid) {
    if (_draft != null) return;
    final seed = persisted?.withUniqueIds() ??
        NutritionPlan(
          id: '${trainerUid}_${widget.athleteId}',
          trainerId: trainerUid,
          athleteId: widget.athleteId,
          title: '',
          meals: defaultPresetMeals(),
          updatedAt: DateTime(2000),
        );
    _draft = seed;
    _baseline = seed;
  }

  // ── Salida ──────────────────────────────────────────────────────────────

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/coach/athlete/${widget.athleteId}');
    }
  }

  Future<void> _handleBack() async {
    if (!_dirty) {
      _leave();
      return;
    }
    final discard = await _confirmDiscard();
    if (discard && mounted) _leave();
  }

  Future<bool> _confirmDiscard() {
    final l10n = AppL10n.of(context);
    return showTreinoConfirmDialog(
      context,
      title: l10n.trainerNutritionEditorDiscardTitle,
      body: l10n.trainerNutritionEditorDiscardBody,
      confirmLabel: l10n.trainerNutritionEditorDiscardConfirm,
    );
  }

  // ── Guardado ────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null || _saving) return;
    final l10n = AppL10n.of(context);
    final clean = draft.sanitizeForSave();
    if (clean.meals.isEmpty) {
      showTreinoToast(
        context,
        l10n.trainerNutritionEditorEmptyPlan,
        bottomOffset: _kAltoDelPie,
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await ref.read(nutritionPlanRepositoryProvider).save(clean);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _draft = clean;
        _baseline = clean;
      });
      // Sin `bottomOffset`: se ve en la ficha, que no tiene el pie.
      showTreinoToast(
        context,
        l10n.trainerNutritionEditorSaved,
        type: TreinoToastType.success,
      );
      _leave();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showTreinoToast(
        context,
        l10n.trainerNutritionEditorSaveError,
        type: TreinoToastType.error,
        bottomOffset: _kAltoDelPie,
      );
    }
  }

  // ── Mutaciones del borrador ─────────────────────────────────────────────

  void _setDraft(NutritionPlan Function(NutritionPlan) change) {
    setState(() => _draft = change(_draft!));
  }

  void _updateMeal(String mealId, Meal Function(Meal) change) {
    _setDraft((plan) => plan.copyWith(meals: [
          for (final meal in plan.meals)
            if (meal.id == mealId) change(meal) else meal,
        ]));
  }

  void _updateGroup(
    String mealId,
    String groupId,
    FoodGroup Function(FoodGroup) change,
  ) {
    _updateMeal(
      mealId,
      (meal) => meal.copyWith(groups: [
        for (final group in meal.groups)
          if (group.id == groupId) change(group) else group,
      ]),
    );
  }

  void _addMeal() {
    _setDraft((plan) => plan.copyWith(meals: [
          ...plan.meals,
          // Nombre vacío a propósito: el hint dice «Nombre de la comida», y si
          // el PF no la completa `sanitizeForSave` la descarta al guardar.
          Meal(id: plan.nextFreeId('meal'), name: '', time: '', groups: []),
        ]));
  }

  void _addGroup(String mealId) {
    final id = _draft!.nextFreeId('group');
    _updateMeal(
      mealId,
      (meal) => meal.copyWith(groups: [
        ...meal.groups,
        FoodGroup(
          id: id,
          name: '',
          selectionMode: SelectionMode.chooseOne,
          options: const [],
        ),
      ]),
    );
  }

  Future<void> _removeMeal(Meal meal) async {
    final hasOptions = meal.groups.any((g) => g.options.isNotEmpty);
    if (hasOptions) {
      final l10n = AppL10n.of(context);
      final ok = await showTreinoConfirmDialog(
        context,
        title: _deleteTitle(meal.name, l10n.trainerNutritionEditorMealNameHint),
        body: l10n.trainerNutritionEditorDeleteMealBody,
        confirmLabel: l10n.commonDelete,
      );
      if (!ok || !mounted) return;
    }
    _setDraft((plan) => plan.copyWith(
          meals: [
            for (final m in plan.meals)
              if (m.id != meal.id) m,
          ],
        ));
  }

  Future<void> _removeGroup(String mealId, FoodGroup group) async {
    if (group.options.isNotEmpty) {
      final l10n = AppL10n.of(context);
      final ok = await showTreinoConfirmDialog(
        context,
        title:
            _deleteTitle(group.name, l10n.trainerNutritionEditorGroupNameHint),
        body: l10n.trainerNutritionEditorDeleteGroupBody,
        confirmLabel: l10n.commonDelete,
      );
      if (!ok || !mounted) return;
    }
    _updateMeal(
      mealId,
      (meal) => meal.copyWith(groups: [
        for (final g in meal.groups)
          if (g.id != group.id) g,
      ]),
    );
  }

  String _deleteTitle(String name, String fallback) {
    final trimmed = name.trim();
    return AppL10n.of(context).trainerNutritionEditorDeleteTitle(
        trimmed.isEmpty ? fallback : trimmed);
  }

  /// Abre el sheet de una opción. Con [option] `null` carga una nueva.
  Future<void> _editOption(
    String mealId,
    String groupId, {
    FoodOption? option,
  }) async {
    FocusScope.of(context).unfocus();
    final palette = AppPalette.of(context);
    final result = await showModalBottomSheet<_OptionSheetResult>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: palette.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => _FoodOptionSheet(
        initial: option,
        newId: option?.id ?? _draft!.nextFreeId('opt'),
      ),
    );
    if (result == null || !mounted) return;
    _updateGroup(mealId, groupId, (group) {
      switch (result) {
        case _OptionSaved(:final saved):
          final exists = group.options.any((o) => o.id == saved.id);
          return group.copyWith(
            options: exists
                ? [
                    for (final o in group.options)
                      if (o.id == saved.id) saved else o,
                  ]
                : [...group.options, saved],
          );
        case _OptionDeleted():
          return group.copyWith(options: [
            for (final o in group.options)
              if (o.id != option?.id) o,
          ]);
      }
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final trainerUid = ref.watch(currentUidProvider);
    if (trainerUid == null || trainerUid.isEmpty) {
      return const SizedBox.shrink();
    }
    final provider = nutritionPlanProvider(
      (trainerId: trainerUid, athleteId: widget.athleteId),
    );
    final planAsync = ref.watch(provider);
    // El error GANA sobre un valor previo (#1581). Riverpod conserva el valor
    // viejo dentro del `AsyncError`: con la copia buena del plan en la caché
    // del teléfono y el doc que el servidor devuelve ilegible, `hasValue` da
    // true, y sembrar de ahí dejaba GUARDAR pisando el doc del servidor con
    // la copia vieja.
    final readFailed = planAsync.hasError;
    if (planAsync.hasValue && !readFailed) {
      _seedIfNeeded(planAsync.requireValue, trainerUid);
    } else if (readFailed && _draft != null && !_dirty) {
      // Carrera: se sembró con la copia de la caché y el servidor falló
      // después. Sin ediciones del PF no hay nada que perder: se descarta el
      // borrador y se muestra el error.
      _draft = null;
      _baseline = null;
    }
    final draft = _draft;
    // Con ediciones del PF el borrador se conserva —no se le tira su
    // trabajo—, pero GUARDAR queda bloqueado mientras la lectura esté en
    // error: guardaría encima de un plan que no se pudo leer. Si Reintentar
    // lee bien, se desbloquea.
    final saveBlocked = readFailed && draft != null;

    final Widget body;
    final String bodyKey;
    if (draft != null) {
      bodyKey = 'form';
      final form = _PlanForm(
        plan: draft,
        onTitleChanged: (v) => _setDraft((p) => p.copyWith(title: v)),
        onMealChanged: _updateMeal,
        onGroupChanged: _updateGroup,
        onRemoveMeal: _removeMeal,
        onRemoveGroup: _removeGroup,
        onAddMeal: _addMeal,
        onAddGroup: _addGroup,
        onEditOption: _editOption,
      );
      body = !saveBlocked
          ? form
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StaleReadBanner(
                  message: l10n.trainerNutritionEditorStaleReadError,
                  retryLabel: l10n.coachRetryLabel,
                  onRetry: () => ref.invalidate(provider),
                ),
                Expanded(child: form),
              ],
            );
    } else if (planAsync.hasError) {
      bodyKey = 'error';
      body = _LoadError(
        message: l10n.trainerNutritionLoadError,
        retryLabel: l10n.coachRetryLabel,
        onRetry: () => ref.invalidate(provider),
      );
    } else {
      bodyKey = 'loading';
      body = Center(child: CircularProgressIndicator(color: palette.accent));
    }

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirmDiscard();
        if (discard && mounted) _leave();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(athleteId: widget.athleteId, onBack: _handleBack),
          Expanded(
            child: TreinoStateSwitcher(
              childKey: ValueKey(bodyKey),
              child: body,
            ),
          ),
          if (draft != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                20,
                _kPieArriba,
                20,
                _kPieAbajo,
              ),
              child: ElevatedButton(
                onPressed: _saving || saveBlocked ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: TreinoButtonTokens.foreground(context),
                  disabledBackgroundColor:
                      palette.accent.withValues(alpha: 0.3),
                  minimumSize: const Size.fromHeight(_kAltoBoton),
                  shape: const StadiumBorder(),
                ),
                child: _saving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: TreinoButtonTokens.foreground(context),
                        ),
                      )
                    : Text(
                        l10n.trainerNutritionEditorSave,
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: AppTextSize.body,
                          letterSpacing: 0.8,
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────

class _Header extends ConsumerWidget {
  const _Header({required this.athleteId, required this.onBack});

  final String athleteId;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    // El nombre del alumno debajo del título: el PF llega desde la ficha de
    // un alumno, pero un plan nutricional se parece mucho al de otro, y
    // guardarlo en el equivocado no avisa nada.
    final name = ref
        .watch(userPublicProfileProvider(athleteId))
        .valueOrNull
        ?.displayName
        ?.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(TreinoIcon.back, color: palette.textPrimary),
            tooltip: AppL10n.of(context).commonBack,
            onPressed: onBack,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppL10n.of(context).trainerNutritionEditorTitle,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: AppTextSize.heading,
                    letterSpacing: 1.2,
                    color: palette.textPrimary,
                  ),
                ),
                if (name != null && name.isNotEmpty)
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.barlow(
                      fontSize: AppTextSize.bodyDense,
                      fontWeight: FontWeight.w600,
                      color: palette.textMuted,
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

// ── Form ──────────────────────────────────────────────────────────────────

class _PlanForm extends StatelessWidget {
  const _PlanForm({
    required this.plan,
    required this.onTitleChanged,
    required this.onMealChanged,
    required this.onGroupChanged,
    required this.onRemoveMeal,
    required this.onRemoveGroup,
    required this.onAddMeal,
    required this.onAddGroup,
    required this.onEditOption,
  });

  final NutritionPlan plan;
  final ValueChanged<String> onTitleChanged;
  final void Function(String mealId, Meal Function(Meal) change) onMealChanged;
  final void Function(
    String mealId,
    String groupId,
    FoodGroup Function(FoodGroup) change,
  ) onGroupChanged;
  final ValueChanged<Meal> onRemoveMeal;
  final void Function(String mealId, FoodGroup group) onRemoveGroup;
  final VoidCallback onAddMeal;
  final ValueChanged<String> onAddGroup;
  final void Function(String mealId, String groupId, {FoodOption? option})
      onEditOption;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    // SingleChildScrollView + Column y no ListView: un ListView desmonta los
    // campos que salen del cacheExtent, y con ellos el foco y la posición del
    // cursor del que estabas escribiendo. Un plan tiene pocas comidas.
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            initialValue: plan.title,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 199, // rules: `title.size() < 200`
            decoration: _fieldDecoration(
              palette,
              label: l10n.trainerNutritionEditorPlanTitleLabel,
              hint: l10n.trainerNutritionEditorPlanTitleHint,
            ).copyWith(counterText: ''),
            style: _fieldStyle(palette),
            onChanged: onTitleChanged,
          ),
          const SizedBox(height: 18),
          for (final meal in plan.meals) ...[
            // La key por id es lo que mantiene cada campo pegado a SU comida:
            // sin ella, borrar la primera hace que Flutter reuse su estado
            // (y su texto) para la que pasa a ocupar ese lugar.
            _MealEditor(
              key: ValueKey(meal.id),
              meal: meal,
              onChanged: (change) => onMealChanged(meal.id, change),
              onGroupChanged: (groupId, change) =>
                  onGroupChanged(meal.id, groupId, change),
              onRemove: () => onRemoveMeal(meal),
              onRemoveGroup: (group) => onRemoveGroup(meal.id, group),
              onAddGroup: () => onAddGroup(meal.id),
              onEditOption: (groupId, {option}) =>
                  onEditOption(meal.id, groupId, option: option),
            ),
            const SizedBox(height: 14),
          ],
          OutlinedButton.icon(
            onPressed: onAddMeal,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: palette.accent),
              foregroundColor: palette.accentText,
              minimumSize: const Size.fromHeight(48),
              shape: const StadiumBorder(),
            ),
            icon: Icon(TreinoIcon.plus, size: 18, color: palette.accentText),
            label: Text(
              l10n.trainerNutritionEditorAddMeal,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: AppTextSize.bodyDense,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MealEditor extends StatelessWidget {
  const _MealEditor({
    super.key,
    required this.meal,
    required this.onChanged,
    required this.onGroupChanged,
    required this.onRemove,
    required this.onRemoveGroup,
    required this.onAddGroup,
    required this.onEditOption,
  });

  final Meal meal;
  final ValueChanged<Meal Function(Meal)> onChanged;
  final void Function(String groupId, FoodGroup Function(FoodGroup) change)
      onGroupChanged;
  final VoidCallback onRemove;
  final ValueChanged<FoodGroup> onRemoveGroup;
  final VoidCallback onAddGroup;
  final void Function(String groupId, {FoodOption? option}) onEditOption;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: meal.name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: _fieldDecoration(
                    palette,
                    hint: l10n.trainerNutritionEditorMealNameHint,
                  ),
                  style: GoogleFonts.barlow(
                    fontSize: AppTextSize.body,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                  onChanged: (v) => onChanged((m) => m.copyWith(name: v)),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: TextFormField(
                  initialValue: meal.time ?? '',
                  keyboardType: TextInputType.datetime,
                  decoration: _fieldDecoration(
                    palette,
                    hint: l10n.trainerNutritionEditorMealTimeHint,
                  ),
                  style: _fieldStyle(palette),
                  onChanged: (v) => onChanged((m) => m.copyWith(time: v)),
                ),
              ),
              IconButton(
                icon: const Icon(TreinoIcon.trash, size: 18),
                color: palette.textMuted,
                tooltip: l10n.trainerNutritionEditorDeleteMealTooltip,
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
              ),
            ],
          ),
          for (final group in meal.groups) ...[
            const SizedBox(height: 12),
            _GroupEditor(
              key: ValueKey(group.id),
              group: group,
              onChanged: (change) => onGroupChanged(group.id, change),
              onRemove: () => onRemoveGroup(group),
              onEditOption: ({option}) =>
                  onEditOption(group.id, option: option),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: _TextAction(
              label: l10n.trainerNutritionEditorAddGroup,
              onTap: onAddGroup,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupEditor extends StatelessWidget {
  const _GroupEditor({
    super.key,
    required this.group,
    required this.onChanged,
    required this.onRemove,
    required this.onEditOption,
  });

  final FoodGroup group;
  final ValueChanged<FoodGroup Function(FoodGroup)> onChanged;
  final VoidCallback onRemove;
  final void Function({FoodOption? option}) onEditOption;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: group.name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: _fieldDecoration(
                    palette,
                    hint: l10n.trainerNutritionEditorGroupNameHint,
                  ),
                  style: GoogleFonts.barlow(
                    fontSize: AppTextSize.bodyDense,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                  onChanged: (v) => onChanged((g) => g.copyWith(name: v)),
                ),
              ),
              IconButton(
                icon: const Icon(TreinoIcon.trash, size: 18),
                color: palette.textMuted,
                tooltip: l10n.trainerNutritionEditorDeleteGroupTooltip,
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (mode, label) in [
                (SelectionMode.chooseOne, l10n.trainerNutritionEditorChooseOne),
                (SelectionMode.all, l10n.trainerNutritionEditorAll),
              ])
                _ModeChip(
                  label: label,
                  selected: group.selectionMode == mode,
                  onSelected: () =>
                      onChanged((g) => g.copyWith(selectionMode: mode)),
                ),
            ],
          ),
          if (group.options.isEmpty) ...[
            const SizedBox(height: 12),
            Text(
              l10n.trainerNutritionEditorEmptyGroup,
              style: GoogleFonts.barlow(
                fontSize: AppTextSize.caption,
                color: palette.textMuted,
              ),
            ),
          ],
          for (final option in group.options) ...[
            const SizedBox(height: 8),
            _OptionRow(
              key: ValueKey(option.id),
              option: option,
              onTap: () => onEditOption(option: option),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: _TextAction(
              label: l10n.trainerNutritionEditorAddOption,
              onTap: () => onEditOption(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // Mismo ChoiceChip que la cadencia del sheet de cobro: acento de fondo con
    // tinta invariante encima, nunca `palette.bg` (1.57:1 en el tema claro).
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onSelected(),
      selectedColor: palette.accent,
      backgroundColor: palette.bgCard,
      labelStyle: GoogleFonts.barlow(
        fontSize: AppTextSize.bodyDense,
        fontWeight: FontWeight.w600,
        color: selected ? TreinoButtonTokens.ink : palette.textPrimary,
      ),
      side: BorderSide(color: selected ? palette.accent : palette.border),
    );
  }
}

/// Una opción como la va a leer el alumno; se toca para editarla.
class _OptionRow extends StatelessWidget {
  const _OptionRow({super.key, required this.option, required this.onTap});

  final FoodOption option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final amount = [option.quantity, option.unit]
        .map((s) => s?.trim() ?? '')
        .where((s) => s.isNotEmpty)
        .join(' ');
    final notes = option.notes?.trim() ?? '';

    return Semantics(
      button: true,
      child: TreinoTappable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: palette.bg,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.name,
                      style: GoogleFonts.barlow(
                        fontSize: AppTextSize.body,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                    if (amount.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.hairline),
                      Text(
                        amount,
                        style: GoogleFonts.barlow(
                          fontSize: AppTextSize.bodyDense,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.hairline),
                      Text(
                        notes,
                        style: GoogleFonts.barlow(
                          fontSize: AppTextSize.caption,
                          color: palette.textFaint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(TreinoIcon.edit, size: 16, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Semantics(
      button: true,
      child: TreinoTappable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            label,
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w600,
              fontSize: AppTextSize.bodyDense,
              color: palette.accentText,
            ),
          ),
        ),
      ),
    );
  }
}

/// Aviso arriba del formulario cuando la lectura falló con el PF ya editando.
class _StaleReadBanner extends StatelessWidget {
  const _StaleReadBanner({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.barlow(
                  fontSize: AppTextSize.bodyDense,
                  color: palette.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.barlow(
                fontSize: AppTextSize.body,
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}

// ── Option sheet ──────────────────────────────────────────────────────────

sealed class _OptionSheetResult {
  const _OptionSheetResult();
}

final class _OptionSaved extends _OptionSheetResult {
  const _OptionSaved(this.saved);

  final FoodOption saved;
}

final class _OptionDeleted extends _OptionSheetResult {
  const _OptionDeleted();
}

class _FoodOptionSheet extends StatefulWidget {
  const _FoodOptionSheet({required this.initial, required this.newId});

  /// La opción que se edita, o `null` para cargar una nueva.
  final FoodOption? initial;

  /// Id de la opción que se devuelve: el de [initial] o uno libre del plan.
  final String newId;

  @override
  State<_FoodOptionSheet> createState() => _FoodOptionSheetState();
}

class _FoodOptionSheetState extends State<_FoodOptionSheet> {
  late final TextEditingController _name;
  late final TextEditingController _quantity;
  late final TextEditingController _unit;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '')
      ..addListener(_onNameChanged);
    _quantity = TextEditingController(text: initial?.quantity ?? '');
    _unit = TextEditingController(text: initial?.unit ?? '');
    _notes = TextEditingController(text: initial?.notes ?? '');
  }

  void _onNameChanged() => setState(() {});

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _unit.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _canSubmit => _name.text.trim().isNotEmpty;

  void _submit() {
    if (!_canSubmit) return;
    String? optional(TextEditingController c) {
      final v = c.text.trim();
      return v.isEmpty ? null : v;
    }

    Navigator.of(context).pop(
      _OptionSaved(
        FoodOption(
          id: widget.newId,
          name: _name.text.trim(),
          quantity: optional(_quantity),
          unit: optional(_unit),
          notes: optional(_notes),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final editing = widget.initial != null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: AppSpacing.hairline,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
            Text(
              editing
                  ? l10n.trainerNutritionOptionEditTitle
                  : l10n.trainerNutritionOptionNewTitle,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: AppTextSize.title,
                letterSpacing: 1.2,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 18),
            _SheetField(
              label: l10n.trainerNutritionOptionNameLabel,
              hint: l10n.trainerNutritionOptionNameHint,
              controller: _name,
              autofocus: !editing,
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _SheetField(
                    label: l10n.trainerNutritionOptionQuantityLabel,
                    hint: l10n.trainerNutritionOptionQuantityHint,
                    controller: _quantity,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SheetField(
                    label: l10n.trainerNutritionOptionUnitLabel,
                    hint: l10n.trainerNutritionOptionUnitHint,
                    controller: _unit,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SheetField(
              label: l10n.trainerNutritionOptionNotesLabel,
              hint: l10n.trainerNutritionOptionNotesHint,
              controller: _notes,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _canSubmit ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: TreinoButtonTokens.foreground(context),
                disabledBackgroundColor: palette.accent.withValues(alpha: 0.3),
                minimumSize: const Size.fromHeight(48),
                shape: const StadiumBorder(),
              ),
              child: Text(
                l10n.trainerNutritionOptionDone,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: AppTextSize.body,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            if (editing) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(const _OptionDeleted()),
                child: Text(
                  l10n.trainerNutritionOptionDelete,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: AppTextSize.body,
                    letterSpacing: 1.4,
                    color: palette.dangerText,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SheetField extends StatelessWidget {
  const _SheetField({
    required this.label,
    required this.hint,
    required this.controller,
    this.autofocus = false,
    this.onSubmitted,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: AppTextSize.caption,
            letterSpacing: 1.4,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          autofocus: autofocus,
          textCapitalization: TextCapitalization.sentences,
          textInputAction:
              onSubmitted == null ? TextInputAction.next : TextInputAction.done,
          onSubmitted: onSubmitted,
          decoration: _fieldDecoration(palette, hint: hint),
          style: _fieldStyle(palette),
        ),
      ],
    );
  }
}

// ── Campos ────────────────────────────────────────────────────────────────

TextStyle _fieldStyle(AppPalette palette) => GoogleFonts.barlow(
      fontSize: AppTextSize.body,
      color: palette.textPrimary,
    );

InputDecoration _fieldDecoration(
  AppPalette palette, {
  String? label,
  required String hint,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    isDense: true,
    labelText: label,
    labelStyle: GoogleFonts.barlow(color: palette.textMuted),
    hintText: hint,
    hintStyle: GoogleFonts.barlow(
      fontSize: AppTextSize.bodyDense,
      color: palette.textMuted,
    ),
    filled: true,
    fillColor: palette.bg,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    enabledBorder: border(palette.border),
    focusedBorder: border(palette.accent, 1.5),
  );
}
