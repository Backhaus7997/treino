import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/tokens/tokens.dart';
import '../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../application/nutrition_plan_providers.dart';
import '../domain/nutrition_plan.dart';

/// Plan nutricional que el alumno recibe de su PF.
///
/// Es deliberadamente read-only: la edición vive en el Coach Hub.
class AthleteNutritionPlanScreen extends ConsumerWidget {
  const AthleteNutritionPlanScreen({
    super.key,
    required this.trainerId,
    required this.athleteId,
  });

  final String trainerId;
  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final provider = nutritionPlanProvider(
      (trainerId: trainerId, athleteId: athleteId),
    );
    final planAsync = ref.watch(provider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(title: l10n.athleteNutritionPlanScreenTitle),
        Expanded(
          child: TreinoStateSwitcher(
            childKey: ValueKey(
              planAsync.when(
                loading: () => 'loading',
                error: (_, __) => 'error',
                data: (plan) => plan == null ? 'empty' : 'data',
              ),
            ),
            child: planAsync.when(
              loading: () => Center(
                child: CircularProgressIndicator(color: palette.accent),
              ),
              error: (_, __) => _MessageState(
                message: l10n.athleteNutritionPlanLoadError,
                retryLabel: l10n.coachRetryLabel,
                onRetry: () => ref.invalidate(provider),
              ),
              data: (plan) => plan == null
                  ? _MessageState(
                      message: l10n.athleteNutritionPlanEmpty,
                    )
                  : _PlanList(plan: plan),
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(TreinoIcon.back, color: palette.textPrimary),
            onPressed: () => _safePopOrCoach(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: AppTextSize.heading,
                letterSpacing: 1.2,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanList extends StatelessWidget {
  const _PlanList({required this.plan});

  final NutritionPlan plan;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Text(
          plan.title.toUpperCase(),
          style: GoogleFonts.barlowCondensed(
            fontSize: AppTextSize.titleLarge,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 18),
        for (var index = 0; index < plan.meals.length; index++) ...[
          _MealCard(meal: plan.meals[index]),
          if (index != plan.meals.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.meal});

  final Meal meal;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final time = meal.time?.trim();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  meal.name.toUpperCase(),
                  style: GoogleFonts.barlowCondensed(
                    fontSize: AppTextSize.title,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              if (time != null && time.isNotEmpty)
                Text(
                  time,
                  style: GoogleFonts.barlow(
                    fontSize: AppTextSize.bodyDense,
                    fontWeight: FontWeight.w600,
                    color: palette.textMuted,
                  ),
                ),
            ],
          ),
          for (final group in meal.groups) ...[
            const SizedBox(height: 18),
            _FoodGroupSection(group: group),
          ],
        ],
      ),
    );
  }
}

class _FoodGroupSection extends StatelessWidget {
  const _FoodGroupSection({required this.group});

  final FoodGroup group;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final hint = switch (group.selectionMode) {
      SelectionMode.chooseOne => l10n.athleteNutritionChooseOneHint,
      SelectionMode.all => l10n.athleteNutritionAllHint,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          group.name.toUpperCase(),
          style: GoogleFonts.barlowCondensed(
            fontSize: AppTextSize.body,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          hint,
          style: GoogleFonts.barlow(
            fontSize: AppTextSize.caption,
            fontWeight: FontWeight.w600,
            color: palette.accentText,
          ),
        ),
        for (final option in group.options) ...[
          const SizedBox(height: 12),
          _FoodOptionRow(option: option),
        ],
      ],
    );
  }
}

class _FoodOptionRow extends StatelessWidget {
  const _FoodOptionRow({required this.option});

  final FoodOption option;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final quantity = option.quantity?.trim();
    final unit = option.unit?.trim();
    final notes = option.notes?.trim();
    final hasAmount = quantity != null &&
        quantity.isNotEmpty &&
        unit != null &&
        unit.isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(TreinoIcon.check, size: 14, color: palette.accentText),
        const SizedBox(width: 8),
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
              if (hasAmount) ...[
                const SizedBox(height: AppSpacing.hairline),
                Text(
                  '$quantity $unit',
                  style: GoogleFonts.barlow(
                    fontSize: AppTextSize.bodyDense,
                    color: palette.textMuted,
                  ),
                ),
              ],
              if (notes != null && notes.isNotEmpty) ...[
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
      ],
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.message,
    this.retryLabel,
    this.onRetry,
  });

  final String message;
  final String? retryLabel;
  final VoidCallback? onRetry;

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
            if (retryLabel != null && onRetry != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onRetry, child: Text(retryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

void _safePopOrCoach(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/coach');
  }
}
