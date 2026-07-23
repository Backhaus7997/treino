import 'package:flutter/material.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/components/treino_transparent_tokens.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_shimmer.dart';
import 'package:treino/core/widgets/motion/treino_tappable.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/domain/nutrition_plan.dart';

/// Card del plan de nutrición activo — tab Nutrición, Fase 3 WU-08
/// (extraído de `_NutricionTabState.build`, `alumno_detail_screen.dart`,
/// ADR-A3-04). Editor de título + comidas + grupos + opciones, 100% lógica
/// de negocio preservada (mutators viven en el screen, este widget solo
/// resuelve presentación).
class PlanNutricionCard extends StatelessWidget {
  const PlanNutricionCard({
    super.key,
    required this.draft,
    required this.palette,
    required this.newIdFor,
    required this.onTitleChanged,
    required this.onMealChanged,
    required this.onRemoveMeal,
    required this.onAddMeal,
  });

  final NutritionPlan draft;
  final AppPalette palette;
  final String Function(String prefix) newIdFor;
  final ValueChanged<String> onTitleChanged;
  final void Function(String mealId, Meal updated) onMealChanged;
  final ValueChanged<String> onRemoveMeal;
  final VoidCallback onAddMeal;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Plan de alimentación', // i18n: Fase W2
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.hairline),
        Text(
          'Armá el plan por comidas, grupos y opciones. Solo vos lo ves.', // i18n: Fase W2
          style: TextStyle(color: palette.textMuted, fontSize: 13),
        ),
        const SizedBox(height: AppSpacing.s14),
        TextFormField(
          initialValue: draft.title,
          decoration: InputDecoration(
            labelText: 'Título del plan (opcional)', // i18n: Fase W2
            hintText:
                'Ej: Progresión 4 - Semana 9 en adelante', // i18n: Fase W2
            labelStyle: TextStyle(color: palette.textMuted),
            hintStyle: TextStyle(
              color: palette.textMuted.withValues(alpha: 0.6),
            ),
            filled: true,
            fillColor: palette.bgCard,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: BorderSide(color: palette.border),
            ),
          ),
          style: TextStyle(color: palette.textPrimary, fontSize: 14),
          onChanged: onTitleChanged,
        ),
        const SizedBox(height: AppSpacing.s14),
        for (final meal in draft.meals)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s12),
            child: _MealEditor(
              meal: meal,
              palette: palette,
              newIdFor: newIdFor,
              onChanged: (u) => onMealChanged(meal.id, u),
              onDelete: () => onRemoveMeal(meal.id),
            ),
          ),
        const SizedBox(height: AppSpacing.hairline),
        OutlinedButton.icon(
          onPressed: onAddMeal,
          icon: const Icon(TreinoIcon.plus, size: 16),
          label: const Text('AGREGAR COMIDA'), // i18n: Fase W2
          style: OutlinedButton.styleFrom(
            foregroundColor: palette.accent,
            side: BorderSide(color: palette.accent),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s18,
              vertical: AppSpacing.s12,
            ),
            shape: const StadiumBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.s20),
      ],
    );
  }
}

/// Skeleton shimmer del [PlanNutricionCard] mientras el plan aún no llega
/// del stream (nunca un `CircularProgressIndicator` seco — Fase 3 WU-08).
class PlanNutricionCardSkeleton extends StatelessWidget {
  const PlanNutricionCardSkeleton({super.key, required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return TreinoShimmer(
      child: Column(
        key: const Key('plan_nutricion_skeleton'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: palette.bgCard,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
          ),
          const SizedBox(height: AppSpacing.s14),
          for (var i = 0; i < 3; i++) ...[
            Container(
              height: 96,
              decoration: BoxDecoration(
                color: palette.bgCard,
                border: Border.all(color: palette.border),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            if (i < 2) const SizedBox(height: AppSpacing.s12),
          ],
        ],
      ),
    );
  }
}

/// Editor de una comida (nombre + hora + grupos). Se colapsa con un
/// ExpansionTile para que el PF pueda tener muchas comidas y no perder el
/// foco.
class _MealEditor extends StatelessWidget {
  const _MealEditor({
    required this.meal,
    required this.palette,
    required this.newIdFor,
    required this.onChanged,
    required this.onDelete,
  });

  final Meal meal;
  final AppPalette palette;
  final String Function(String prefix) newIdFor;
  final ValueChanged<Meal> onChanged;
  final VoidCallback onDelete;

  void _updateGroup(FoodGroup updated) {
    onChanged(meal.copyWith(
      groups: meal.groups
          .map((g) => g.id == updated.id ? updated : g)
          .toList(growable: false),
    ));
  }

  void _removeGroup(String groupId) {
    onChanged(meal.copyWith(
      groups: meal.groups.where((g) => g.id != groupId).toList(),
    ));
  }

  void _addGroup() {
    onChanged(meal.copyWith(groups: [
      ...meal.groups,
      FoodGroup(
        id: newIdFor('group'),
        // Vacío intencional — placeholder "Nuevo grupo" en el hintText del
        // TextFormField. Sin nombre real, el sanitize dropea el grupo.
        name: '',
        selectionMode: SelectionMode.chooseOne,
        options: const [],
      ),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Theme(
        // Quitar los divisores default y el splash raro del ExpansionTile.
        data: Theme.of(context).copyWith(
          dividerColor: TreinoTransparentTokens.value,
          splashColor: TreinoTransparentTokens.value,
          highlightColor: TreinoTransparentTokens.value,
        ),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.s14),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.s14,
            0,
            AppSpacing.s14,
            AppSpacing.s14,
          ),
          iconColor: palette.textMuted,
          collapsedIconColor: palette.textMuted,
          title: Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: meal.name,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Nombre de la comida', // i18n: Fase W2
                    hintStyle: TextStyle(
                      color: palette.textMuted.withValues(alpha: 0.6),
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  onChanged: (v) => onChanged(meal.copyWith(name: v)),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              SizedBox(
                width: 100,
                child: TextFormField(
                  initialValue: meal.time ?? '',
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Hora', // i18n: Fase W2
                    hintStyle: TextStyle(
                      color: palette.textMuted.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                    prefixIcon: Icon(TreinoIcon.clock,
                        size: 14, color: palette.textMuted),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 22, minHeight: 22),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: TextStyle(color: palette.textPrimary, fontSize: 12),
                  onChanged: (v) => onChanged(meal.copyWith(time: v)),
                ),
              ),
              const SizedBox(width: AppSpacing.hairline),
              IconButton(
                tooltip: 'Eliminar comida', // i18n: Fase W2
                onPressed: onDelete,
                icon: Icon(TreinoIcon.trash, size: 16, color: palette.danger),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
          children: [
            for (final group in meal.groups)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s8 + 2),
                child: _GroupEditor(
                  group: group,
                  palette: palette,
                  newIdFor: newIdFor,
                  onChanged: _updateGroup,
                  onDelete: () => _removeGroup(group.id),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addGroup,
                icon: const Icon(TreinoIcon.plus, size: 14),
                label: const Text('AGREGAR GRUPO'), // i18n: Fase W2
                style: TextButton.styleFrom(
                  foregroundColor: palette.accent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s12,
                    vertical: AppSpacing.s8,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Editor de un grupo de alimentos dentro de una comida.
class _GroupEditor extends StatelessWidget {
  const _GroupEditor({
    required this.group,
    required this.palette,
    required this.newIdFor,
    required this.onChanged,
    required this.onDelete,
  });

  final FoodGroup group;
  final AppPalette palette;
  final String Function(String prefix) newIdFor;
  final ValueChanged<FoodGroup> onChanged;
  final VoidCallback onDelete;

  void _updateOption(FoodOption updated) {
    onChanged(group.copyWith(
      options: group.options
          .map((o) => o.id == updated.id ? updated : o)
          .toList(growable: false),
    ));
  }

  void _removeOption(String optionId) {
    onChanged(group.copyWith(
      options: group.options.where((o) => o.id != optionId).toList(),
    ));
  }

  void _addOption() {
    onChanged(group.copyWith(options: [
      ...group.options,
      FoodOption(id: newIdFor('opt'), name: ''),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.bg,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: group.name,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Nombre del grupo', // i18n: Fase W2
                    hintStyle: TextStyle(
                      color: palette.textMuted.withValues(alpha: 0.6),
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                  onChanged: (v) => onChanged(group.copyWith(name: v)),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              _SelectionModeSelector(
                mode: group.selectionMode,
                palette: palette,
                onChanged: (m) => onChanged(group.copyWith(selectionMode: m)),
              ),
              IconButton(
                tooltip: 'Eliminar grupo', // i18n: Fase W2
                onPressed: onDelete,
                icon: Icon(TreinoIcon.trash, size: 14, color: palette.danger),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.hairline + 2),
          for (final option in group.options)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.hairline),
              child: _OptionRow(
                option: option,
                palette: palette,
                onChanged: _updateOption,
                onDelete: () => _removeOption(option.id),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addOption,
              icon: const Icon(TreinoIcon.plus, size: 12),
              label: const Text('AGREGAR OPCIÓN'), // i18n: Fase W2
              style: TextButton.styleFrom(
                foregroundColor: palette.accent,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s8,
                  vertical: AppSpacing.hairline,
                ),
                textStyle: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Toggle compacto entre modo de selección `chooseOne` y `all` — se muestra
/// como dos pills side-by-side.
class _SelectionModeSelector extends StatelessWidget {
  const _SelectionModeSelector({
    required this.mode,
    required this.palette,
    required this.onChanged,
  });

  final SelectionMode mode;
  final AppPalette palette;
  final ValueChanged<SelectionMode> onChanged;

  Widget _pill(String label, bool active, VoidCallback onTap) {
    return TreinoTappable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.hairline - 1,
        ),
        decoration: BoxDecoration(
          color: active
              ? palette.accent.withValues(alpha: 0.18)
              : TreinoTransparentTokens.value,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: active ? palette.accent : palette.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? palette.accent : palette.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _pill(
          'ELEGIR UNA', // i18n: Fase W2
          mode == SelectionMode.chooseOne,
          () => onChanged(SelectionMode.chooseOne),
        ),
        const SizedBox(width: AppSpacing.hairline),
        _pill(
          'TODAS', // i18n: Fase W2
          mode == SelectionMode.all,
          () => onChanged(SelectionMode.all),
        ),
        const SizedBox(width: AppSpacing.hairline),
      ],
    );
  }
}

/// Fila de una opción del grupo: nombre + cantidad + unidad + notas.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.palette,
    required this.onChanged,
    required this.onDelete,
  });

  final FoodOption option;
  final AppPalette palette;
  final ValueChanged<FoodOption> onChanged;
  final VoidCallback onDelete;

  InputDecoration _dec(String hint) => InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(
          color: palette.textMuted.withValues(alpha: 0.6),
          fontSize: 12,
        ),
        filled: true,
        fillColor: palette.bgCard,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s8,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: palette.border),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(color: palette.textPrimary, fontSize: 12);
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: TextFormField(
            initialValue: option.name,
            decoration:
                _dec('Alimento (ej: 5 discos de arroz)'), // i18n: Fase W2
            style: textStyle,
            onChanged: (v) => onChanged(option.copyWith(name: v)),
          ),
        ),
        const SizedBox(width: AppSpacing.hairline + 2),
        Expanded(
          flex: 2,
          child: TextFormField(
            initialValue: option.quantity ?? '',
            decoration: _dec('Cant.'), // i18n: Fase W2
            style: textStyle,
            onChanged: (v) =>
                onChanged(option.copyWith(quantity: v.isEmpty ? null : v)),
          ),
        ),
        const SizedBox(width: AppSpacing.hairline + 2),
        Expanded(
          flex: 3,
          child: TextFormField(
            initialValue: option.unit ?? '',
            decoration: _dec('Unidad (grs, ml…)'), // i18n: Fase W2
            style: textStyle,
            onChanged: (v) =>
                onChanged(option.copyWith(unit: v.isEmpty ? null : v)),
          ),
        ),
        const SizedBox(width: AppSpacing.hairline + 2),
        Expanded(
          flex: 4,
          child: TextFormField(
            initialValue: option.notes ?? '',
            decoration: _dec('Notas (marca, aclaraciones…)'), // i18n: Fase W2
            style: textStyle,
            onChanged: (v) =>
                onChanged(option.copyWith(notes: v.isEmpty ? null : v)),
          ),
        ),
        IconButton(
          tooltip: 'Eliminar opción', // i18n: Fase W2
          onPressed: onDelete,
          icon: Icon(TreinoIcon.trash, size: 12, color: palette.danger),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        ),
      ],
    );
  }
}
