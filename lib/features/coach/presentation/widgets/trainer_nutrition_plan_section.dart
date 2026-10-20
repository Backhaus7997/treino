import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/tokens.dart';
import '../../../../core/utils/argentina_time.dart';
import '../../../../core/utils/date_labels.dart';
import '../../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../../core/widgets/motion/treino_tappable.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../application/nutrition_plan_providers.dart';
import '../../domain/nutrition_plan.dart';

/// Sección PLAN NUTRICIONAL del detalle de alumno mobile del PF (#1538).
///
/// Dice si el alumno ya tiene plan —y de cuándo es— sin entrar al editor, y
/// abre `/coach/athlete/:athleteId/nutricion` para cargarlo o editarlo. Antes
/// esto no existía en mobile: el plan sólo se cargaba desde el Coach Hub web.
///
/// Resuelve su propio async, como el resto de las secciones de la ficha
/// (#503): si la lectura falla, se degrada sólo esta sección.
class TrainerNutritionPlanSection extends ConsumerWidget {
  const TrainerNutritionPlanSection({
    super.key,
    required this.athleteId,
    required this.trainerUid,
  });

  final String athleteId;
  final String trainerUid;

  void _open(BuildContext context) =>
      context.push('/coach/athlete/$athleteId/nutricion');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (trainerUid.isEmpty) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final provider =
        nutritionPlanProvider((trainerId: trainerUid, athleteId: athleteId));
    final planAsync = ref.watch(provider);
    // El error GANA sobre un valor previo, igual que en el `when` de abajo
    // (#1581). Riverpod conserva el valor viejo dentro del `AsyncError`: con
    // la copia buena del plan en la caché del teléfono y un doc que el
    // servidor devuelve ilegible, `hasValue` daba true, y «Editar» abría el
    // editor sobre la copia vieja con GUARDAR habilitado.
    final hasPlanData = planAsync.hasValue && !planAsync.hasError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.trainerNutritionSectionTitle,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: AppTextSize.caption,
                letterSpacing: 1.2,
                color: palette.textMuted,
              ),
            ),
            const Spacer(),
            // Sólo con el dato en la mano: mientras carga, «+ Cargar» sobre un
            // alumno que YA tiene plan le diría al PF que no lo tiene.
            if (hasPlanData)
              Semantics(
                button: true,
                child: TreinoTappable(
                  onTap: () => _open(context),
                  child: Text(
                    planAsync.requireValue == null
                        ? l10n.trainerNutritionSectionLoadCta
                        : l10n.trainerNutritionSectionEditCta,
                    style: GoogleFonts.barlow(
                      fontWeight: FontWeight.w600,
                      fontSize: AppTextSize.bodyDense,
                      color: palette.accentText,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TreinoStateSwitcher(
          childKey: ValueKey(planAsync.when(
            loading: () => 'loading',
            error: (_, __) => 'error',
            data: (plan) => plan == null ? 'empty' : 'data',
          )),
          child: planAsync.when(
            loading: () => _card(
              palette: palette,
              child: _muted(l10n.commonLoading, palette),
            ),
            error: (_, __) => _card(
              palette: palette,
              child: Row(
                children: [
                  Expanded(
                    child: _muted(l10n.trainerNutritionLoadError, palette),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    child: TreinoTappable(
                      onTap: () => ref.invalidate(provider),
                      child: Text(
                        l10n.coachRetryLabel,
                        style: GoogleFonts.barlow(
                          fontWeight: FontWeight.w600,
                          fontSize: AppTextSize.bodyDense,
                          color: palette.accentText,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            data: (plan) => plan == null
                ? _card(
                    palette: palette,
                    onTap: () => _open(context),
                    child: _muted(l10n.trainerNutritionSectionEmpty, palette),
                  )
                : _card(
                    palette: palette,
                    onTap: () => _open(context),
                    child: _PlanSummary(plan: plan),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _muted(String text, AppPalette palette) => Text(
        text,
        style: GoogleFonts.barlow(
          fontSize: AppTextSize.bodyDense,
          color: palette.textMuted,
        ),
      );

  Widget _card({
    required AppPalette palette,
    required Widget child,
    VoidCallback? onTap,
  }) {
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Expanded(child: child),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            Icon(TreinoIcon.chevronRight, size: 18, color: palette.textMuted),
          ],
        ],
      ),
    );
    if (onTap == null) return card;
    return TreinoTappable(onTap: onTap, child: card);
  }
}

class _PlanSummary extends StatelessWidget {
  const _PlanSummary({required this.plan});

  final NutritionPlan plan;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final title = plan.title.trim();
    // `updatedAt` es un instante real, pero el DÍA que se muestra es un bucket
    // de calendario: se deriva en ART y no con la zona del device, o cerca de
    // la medianoche cae en el día equivocado (#392, #671; ver la tabla de
    // `no_raw_clock_scan_test.dart`).
    final updated = toArgentina(plan.updatedAt.toUtc());
    final date = '${updated.day} '
        '${monthAbbrev(updated, l10n.localeName)} ${updated.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.isEmpty ? l10n.trainerNutritionSectionUntitled : title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: AppTextSize.body,
            letterSpacing: 0.4,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.trainerNutritionSectionSummary(plan.meals.length, date),
          style: GoogleFonts.barlow(
            fontSize: AppTextSize.caption,
            color: palette.textMuted,
          ),
        ),
      ],
    );
  }
}
