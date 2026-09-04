import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/motion/treino_fade_slide_in.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../paywall/application/athlete_entitlement_provider.dart';
import '../../../profile/domain/experience_level.dart';
import '../../application/routine_providers.dart';
import '../../application/unified_templates_providers.dart';
import '../onboarding/templates_onboarding_gate.dart';
import 'coach_chip.dart';
import 'level_filter_pills.dart';
import 'premium_chip.dart';
import 'routine_card.dart';
import 'templates_preferences_bar.dart';
import '../../../../app/theme/tokens/primitives.dart';

/// PLANTILLAS tab page (workout redesign slice 2) — EVERY template in one
/// square grid: the linked coach's shared templates first (badged
/// "DE TU COACH", mirroring the RUTINAS pinning) followed by the public
/// system catalog. Replaces the old stacked TrainerTemplatesSection +
/// PlantillasSection pair from the single-page body.
///
/// No section header (the active tab label already reads PLANTILLAS) and no
/// "Ver más" collapse: the page is dedicated to the catalog, so it shows
/// everything. The level pills filter the WHOLE grid, coach templates
/// included.
///
/// Kept alive across tab swipes ([AutomaticKeepAliveClientMixin]) on
/// purpose: without it, every TU ENTRENO⇄PLANTILLAS swipe would tear down
/// and re-subscribe the coach-templates stream, making the coach cards pop
/// in late on every visit — a flicker the old always-mounted sections never
/// had. Keeping the page alive preserves that baseline: the (autoDispose)
/// provider chain lives exactly as long as `/workout` stays mounted and is
/// released when the athlete leaves the Entrenar tab route.
class PlantillasTab extends ConsumerStatefulWidget {
  const PlantillasTab({super.key});

  @override
  ConsumerState<PlantillasTab> createState() => _PlantillasTabState();
}

class _PlantillasTabState extends ConsumerState<PlantillasTab>
    with AutomaticKeepAliveClientMixin<PlantillasTab> {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // The PLANTILLAS mini-onboarding (#635 PR#2), first entry only.
    //
    // From a post-frame callback because `initState` has no `Localizations`
    // ancestor resolved yet and the navigator cannot present mid-frame. The
    // gate owns every other guard — role, profile readiness, the welcome tour,
    // and the persisted seen-flag — so this call site stays a trigger and
    // nothing more.
    //
    // Fires once per mount of `/workout` rather than once per visit to the tab:
    // `wantKeepAlive` is true, so swiping TU ENTRENO ⇄ PLANTILLAS does not
    // re-run it. That is the intended granularity — the flow is "first time you
    // land here", not "every time you swipe back".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      maybeShowTemplatesOnboarding(context: context, ref: ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    // Rankeado, no sólo filtrado (#635 PR#3): las pills de nivel siguen
    // filtrando, y encima de eso el catálogo se ordena por afinidad con lo que
    // el atleta respondió en el mini-onboarding. Quien no respondió ve el
    // mismo orden de siempre — con preferencias vacías el provider devuelve la
    // lista sin tocar.
    final entriesAsync = ref.watch(rankedUnifiedTemplatesProvider);
    final filter = ref.watch(routinesLevelFilterProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      // SingleChildScrollView + Column (no ListView(children:)): un
      // ListView, aunque construya sus widgets eager, sigue siendo un
      // viewport — los Elements/State de los TreinoFadeSlideIn que salen
      // del cacheExtent se desmontan y re-animan al volver a scrollear.
      // Column dentro de SingleChildScrollView scrollea como una sola
      // unidad, sin reciclar Elements por ítem (ver doc de
      // TreinoFadeSlideIn).
      child: SingleChildScrollView(
        // + bottom inset: the floating bar overlays the body (extendBody),
        // so the last item needs room to scroll out from behind it.
        padding: EdgeInsets.fromLTRB(
          0,
          20,
          0,
          20 + MediaQuery.paddingOf(context).bottom,
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TreinoFadeSlideIn(
              delay: AppMotion.stagger(0),
              child: const LevelFilterPills(),
            ),
            const SizedBox(height: AppSpacing.s8),
            // Por qué la grilla está en ese orden, y cómo cambiarlo (#635 PR#3).
            // Encima de la grilla y debajo de las pills de nivel: el nivel
            // FILTRA (saca cosas), esto ORDENA (no saca nada), y verlos en ese
            // orden es lo que hace legible la diferencia.
            TreinoFadeSlideIn(
              delay: AppMotion.stagger(1),
              child: const TemplatesPreferencesBar(),
            ),
            const SizedBox(height: AppSpacing.s8),
            TreinoFadeSlideIn(
              delay: AppMotion.stagger(2),
              child: entriesAsync.when(
                data: (entries) {
                  if (entries.isEmpty) {
                    final l10n = AppL10n.of(context);
                    final msg = filter == null
                        ? l10n.workoutExploreEmptyAll
                        : l10n.workoutExploreEmptyLevel;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        msg,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    );
                  }
                  return _TemplatesGrid(entries: entries);
                },
                loading: () => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: CircularProgressIndicator(color: palette.accent),
                  ),
                ),
                error: (_, __) => _CatalogErrorState(filter: filter),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Catalog error state. Coach and community templates are independent of the
/// catalog fetch (their own providers), so whatever already resolved stays on
/// screen ABOVE the error message instead of being swallowed by it — the
/// independence the old side-by-side sections had. Only the catalog is in
/// error, and retry re-fetches exactly that.
class _CatalogErrorState extends ConsumerWidget {
  const _CatalogErrorState({required this.filter});

  final ExperienceLevel? filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final coach = ref.watch(coachSharedTemplatesProvider);
    // The level pills keep filtering the whole grid — the surviving coach
    // part included.
    final community = ref.watch(communityTemplatesProvider);
    final coachIds = {for (final r in coach) r.id};
    final entries = <TemplateEntry>[
      for (final r in coach)
        if (filter == null || r.level == filter)
          (routine: r, origin: TemplateOrigin.coach),
      for (final r in community)
        if (!coachIds.contains(r.id) && (filter == null || r.level == filter))
          (routine: r, origin: TemplateOrigin.community),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (entries.isNotEmpty) ...[
          _TemplatesGrid(entries: entries),
          const SizedBox(height: 12),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppL10n.of(context).workoutExploreLoadError,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(routinesProvider),
                child: Text(AppL10n.of(context).plantillasRetryLabel),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 2-up rows in a single-pass [Table] — same layout the old PlantillasSection
/// used (no GridView: hard-coded cell heights overflowed; no per-row
/// [IntrinsicHeight]: its dry-layout re-runs janked the scroll, #402). Equal
/// row heights come from [RoutineCard.reserveTitleLines] making every card
/// deterministic-height; the badge lives inside the card's fixed icon row, so
/// coach cards measure exactly like catalog cards.
class _TemplatesGrid extends ConsumerWidget {
  const _TemplatesGrid({required this.entries});

  final List<TemplateEntry> entries;

  Widget _gridCell(Widget cell, {required bool lastRow}) => Padding(
        padding: EdgeInsets.only(bottom: lastRow ? 0 : 12),
        child: cell,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useSingleColumn = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    // Una sola lectura para toda la grilla: si el catálogo pago está
    // bloqueando a quien mira. Se cruza con el `isPremium` de cada plantilla.
    final catalogLocked = ref.watch(catalogLockActiveProvider);
    final cells = <Widget>[
      for (final entry in entries)
        RoutineCard(
          routine: entry.routine,
          // Coach templates always glow magenta to match their chip (coach
          // ownership speaks highlight — same language as RutinasSection);
          // catalog and community cards keep the hash-based alternation.
          variant: entry.fromCoach || entry.routine.id.hashCode % 3 == 0
              ? RoutineCardVariant.highlight
              : RoutineCardVariant.accent,
          reserveTitleLines: !useSingleColumn,
          badge: switch (entry.origin) {
            TemplateOrigin.coach => CoachChip(routineId: entry.routine.id),
            TemplateOrigin.community => CoachChip(
                routineId: entry.routine.id,
                variant: CoachChipVariant.communityTrainer,
              ),
            // El candado sólo aparece si esta plantilla está bloqueada para
            // QUIEN MIRA: `isPremium` sola no alcanza. Un alumno con derecho
            // ve el catálogo entero sin candados, y con el paywall apagado
            // no lo ve nadie.
            TemplateOrigin.system =>
              catalogLocked && entry.routine.isPremium
                  ? PremiumChip(routineId: entry.routine.id)
                  : null,
          },
        ),
    ];

    if (useSingleColumn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < cells.length; index++)
            _gridCell(cells[index], lastRow: index == cells.length - 1),
        ],
      );
    }

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(),
        1: FixedColumnWidth(12),
        2: FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        for (var row = 0; row < cells.length; row += 2)
          TableRow(
            children: [
              _gridCell(cells[row], lastRow: row + 2 >= cells.length),
              const SizedBox.shrink(),
              if (row + 1 < cells.length)
                _gridCell(
                  cells[row + 1],
                  lastRow: row + 2 >= cells.length,
                )
              else
                const SizedBox.shrink(),
            ],
          ),
      ],
    );
  }
}
