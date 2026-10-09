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
    with
        AutomaticKeepAliveClientMixin<PlantillasTab>,
        SingleTickerProviderStateMixin<PlantillasTab> {
  @override
  bool get wantKeepAlive => true;

  /// Entrada one-shot de la grilla: fade + slide de [AppMotion.slideMd] con el
  /// delay `stagger(2)`, la misma que antes le daba un `TreinoFadeSlideIn`
  /// envolviendo la grilla entera.
  ///
  /// Vive en el State de la pestaña y no en cada fila a propósito: las filas
  /// ahora se arman a demanda (`SliverList.builder`), y una fila que sale del
  /// `cacheExtent` se desmonta y vuelve a montarse al regresar. Con un
  /// `TreinoFadeSlideIn` por fila, cada una re-animaría su entrada en cada
  /// scroll (ver el dartdoc de ese widget). Con el progreso acá, la fila que
  /// se re-monta lee un controller que ya terminó: opacidad 1, translate 0.
  late final AnimationController _gridEntrance;
  late final Animation<double> _gridProgress;
  bool _entranceStarted = false;

  @override
  void initState() {
    super.initState();
    final delay = AppMotion.stagger(2);
    final total = delay + AppMotion.base;
    _gridEntrance = AnimationController(vsync: this, duration: total);
    _gridProgress = CurvedAnimation(
      parent: _gridEntrance,
      curve: Interval(
        delay.inMicroseconds / total.inMicroseconds,
        1,
        curve: AppMotion.standard,
      ),
    );
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Mismo criterio que TreinoFadeSlideIn: reduce-motion necesita MediaQuery,
    // por eso se resuelve acá y no en initState.
    if (!_entranceStarted) {
      _entranceStarted = true;
      if (AppMotion.reduceMotion(context)) {
        _gridEntrance.value = 1;
      } else {
        _gridEntrance.forward();
      }
    } else if (AppMotion.reduceMotion(context) && !_gridEntrance.isCompleted) {
      _gridEntrance
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _gridEntrance.dispose();
    super.dispose();
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

    Widget message(Widget child) => SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: child,
          ),
        );

    final Widget content = entriesAsync.when(
      data: (entries) {
        if (entries.isEmpty) {
          final l10n = AppL10n.of(context);
          final msg = filter == null
              ? l10n.workoutExploreEmptyAll
              : l10n.workoutExploreEmptyLevel;
          return message(
            Text(
              msg,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.textMuted,
              ),
            ),
          );
        }
        return _TemplatesSliverGrid(entries: entries, progress: _gridProgress);
      },
      loading: () => message(
        Center(child: CircularProgressIndicator(color: palette.accent)),
      ),
      error: (_, __) => SliverToBoxAdapter(
        child: _CatalogErrorState(filter: filter),
      ),
    );

    // Un solo CustomScrollView con slivers, no SingleChildScrollView + Column.
    //
    // Con el Column, las 50 plantillas del catálogo (#1393) se construían, se
    // medían y se pintaban TODAS, siempre, y cualquier rebuild de la pestaña
    // las rehacía enteras. El más caro de esos rebuilds pasaba justo al
    // scrollear: la barra flotante se compacta/expande animando su alto, el
    // Scaffold del shell publica ese alto frame a frame en
    // `MediaQuery.padding.bottom`, y esta pestaña leía `paddingOf` en su
    // build — así que cada frame de la animación reconstruía las 50 cards
    // (dos TextPainter por card) y relayouteaba la grilla completa.
    //
    // Ahora las filas se arman a demanda (SliverList.builder) con un
    // RepaintBoundary por fila, y el inset de la barra lo lee SOLO el sliver
    // final ([_ShellBottomInset]): la animación de la barra reconstruye un
    // SizedBox, no la grilla.
    //
    // El encabezado va en un SliverToBoxAdapter: ese sliver no recicla su
    // hijo al salir de pantalla, así que sus TreinoFadeSlideIn siguen siendo
    // one-shot (ver el dartdoc de TreinoFadeSlideIn).
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TreinoFadeSlideIn(
                  delay: AppMotion.stagger(0),
                  child: const LevelFilterPills(),
                ),
                const SizedBox(height: AppSpacing.s8),
                // Por qué la grilla está en ese orden, y cómo cambiarlo (#635
                // PR#3). Encima de la grilla y debajo de las pills de nivel: el
                // nivel FILTRA (saca cosas), esto ORDENA (no saca nada), y
                // verlos en ese orden es lo que hace legible la diferencia.
                TreinoFadeSlideIn(
                  delay: AppMotion.stagger(1),
                  child: const TemplatesPreferencesBar(),
                ),
                const SizedBox(height: AppSpacing.s8),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: content,
        ),
        const _ShellBottomInset(),
      ],
    );
  }
}

/// Hueco final del scroll: 20 de aire + `MediaQuery.padding.bottom`.
///
/// Dentro del shell, ese `padding.bottom` YA es la caja entera de la barra
/// flotante (margen + 8 + alto, ver el dartdoc de `TreinoBottomBar.minHeight`,
/// #830): sumarle el alto de la barra duplicaría el hueco. Fuera del shell da
/// el safe area a secas.
///
/// Es un widget aparte a propósito: es el ÚNICO lector de `paddingOf` en la
/// pestaña. Ese valor cambia en cada frame mientras la barra se compacta o se
/// expande, y leído en el build de la pestaña arrastraba la grilla entera a
/// reconstruirse con él.
class _ShellBottomInset extends StatelessWidget {
  const _ShellBottomInset();

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
        child: SizedBox(height: 20 + MediaQuery.paddingOf(context).bottom),
      );
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

/// Variante de una celda según su origen. Compartida por la grilla lazy y
/// por la del estado de error.
Widget _templateCell(
  TemplateEntry entry, {
  required bool catalogLocked,
  required bool reserveTitleLines,
}) =>
    RoutineCard(
      routine: entry.routine,
      reserveTitleLines: reserveTitleLines,
      // Coach templates always glow magenta to match their chip (coach
      // ownership speaks highlight — same language as RutinasSection);
      // catalog and community cards keep the hash-based alternation.
      variant: entry.fromCoach || entry.routine.id.hashCode % 3 == 0
          ? RoutineCardVariant.highlight
          : RoutineCardVariant.accent,
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
        //
        // La grilla habla del eje SEGUIR y de ninguno más — de ahí el
        // cruce con `isPremium` y el uso de `catalogLockActiveProvider`.
        // Que una de principiante aparezca SIN candado acá y con el botón
        // de "Usar como base" bloqueado en el detalle NO es una
        // discrepancia: seguirla es gratis y copiarla no. El detalle usa
        // `customizeLockActiveProvider`, que es el otro eje. Antes de
        // "arreglar" esta asimetría, leer el dartdoc de los dos providers.
        TemplateOrigin.system => catalogLocked && entry.routine.isPremium
            ? PremiumChip(routineId: entry.routine.id)
            : null,
      },
    );

/// Una fila de la grilla: dos celdas (o una, con texto grande) y 12 de
/// separación debajo, salvo en la última fila.
///
/// Sin Table ni GridView: GridView con alturas fijas desbordaba, e
/// IntrinsicHeight por fila re-corría su dry-layout y trababa el scroll
/// (#402). Las dos celdas miden lo mismo porque [RoutineCard.reserveTitleLines]
/// hace la altura de la card determinística; el badge vive dentro de la fila
/// fija del ícono, así que las cards del coach miden igual que las del
/// catálogo.
Widget _templateRow(
  List<TemplateEntry> entries,
  int row, {
  required bool singleColumn,
  required bool catalogLocked,
}) {
  final perRow = singleColumn ? 1 : 2;
  final first = row * perRow;
  final lastRow = first + perRow >= entries.length;
  Widget cell(int i) => _templateCell(
        entries[i],
        catalogLocked: catalogLocked,
        reserveTitleLines: !singleColumn,
      );

  return Padding(
    padding: EdgeInsets.only(bottom: lastRow ? 0 : 12),
    child: singleColumn
        ? cell(first)
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cell(first)),
              const SizedBox(width: 12),
              Expanded(
                child: first + 1 < entries.length
                    ? cell(first + 1)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
  );
}

int _rowCount(int entries, {required bool singleColumn}) =>
    singleColumn ? entries : (entries + 1) ~/ 2;

/// La grilla de EXPLORAR como sliver: filas armadas a demanda.
///
/// Con 50 plantillas (#1393), sólo se construyen las filas visibles más el
/// `cacheExtent`; el resto no existe hasta que el scroll llega. Cada fila
/// lleva su RepaintBoundary (default de SliverList), así que scrollear no
/// repinta las sombras con blur de las cards que no cambiaron.
class _TemplatesSliverGrid extends ConsumerWidget {
  const _TemplatesSliverGrid({required this.entries, required this.progress});

  final List<TemplateEntry> entries;

  /// Progreso de la entrada one-shot, del State de la pestaña.
  final Animation<double> progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final singleColumn = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    // Una sola lectura para toda la grilla: si el catálogo pago está
    // bloqueando a quien mira. Se cruza con el `isPremium` de cada plantilla.
    final catalogLocked = ref.watch(catalogLockActiveProvider);
    return SliverFadeTransition(
      opacity: progress,
      // Una animación de entrada es decoración: no decide qué existe para el
      // lector de pantalla (mismo criterio que TreinoFadeSlideIn).
      alwaysIncludeSemantics: true,
      sliver: SliverList.builder(
        itemCount: _rowCount(entries.length, singleColumn: singleColumn),
        itemBuilder: (context, row) => AnimatedBuilder(
          animation: progress,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, AppMotion.slideMd * (1 - progress.value)),
            child: child,
          ),
          child: _templateRow(
            entries,
            row,
            singleColumn: singleColumn,
            catalogLocked: catalogLocked,
          ),
        ),
      ),
    );
  }
}

/// Grilla eager para el estado de error: ahí sólo sobreviven las plantillas
/// del coach y de la comunidad, que son pocas, y van dentro de un Column.
class _TemplatesGrid extends ConsumerWidget {
  const _TemplatesGrid({required this.entries});

  final List<TemplateEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final singleColumn = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final catalogLocked = ref.watch(catalogLockActiveProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var row = 0;
            row < _rowCount(entries.length, singleColumn: singleColumn);
            row++)
          _templateRow(
            entries,
            row,
            singleColumn: singleColumn,
            catalogLocked: catalogLocked,
          ),
      ],
    );
  }
}
