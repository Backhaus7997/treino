import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/app_palette.dart';
import '../../core/analytics/sub_tab_analytics.dart';
import '../../core/widgets/motion/treino_fade_slide_in.dart';
import '../profile/application/user_providers.dart';
import '../profile/domain/user_role.dart';
import 'presentation/widgets/historial_section.dart';
import 'presentation/widgets/plantillas_tab.dart';
import 'presentation/widgets/rutinas_section.dart';
import 'trainer_workout_view.dart';

/// Role-aware workout screen.
///
/// - Athlete → 2-page swipeable Entrenar tab (workout redesign slice 2):
///   "Tu entreno" (page 0 — unified routines + history) + "Plantillas"
///   (page 1 — the full template grid, coach-shared + catalog). Same
///   segmented-pill pattern the tab had in the rankings era; rankings itself
///   now lives in the FEED tab (`/feed?tab=rankings`) — see [FeedScreen].
/// - Trainer → [TrainerWorkoutView] dedicated to plan creation. Trainers
///   should not see athlete-mode controls (no EMPEZAR, no historial propio,
///   no template grid); their WORKOUT surface is exclusively for assigning
///   routines.
/// - Loading → empty surface (matches [HomeScreen] / [CoachScreen] pattern).
class WorkoutScreen extends ConsumerWidget {
  const WorkoutScreen({super.key, this.initialTab});

  /// Optional initial sub-tab — accepts `'plantillas'`. Read from the
  /// `?tab=` query param by the `/workout` route builder (mirrors
  /// `CoachScreen.initialTab` / `FeedScreen.initialTab`). Unknown values
  /// fall back to page 0. Ignored for the trainer view.
  final String? initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserRole? role = ref.watch(
      userProfileProvider.select((async) => async.valueOrNull?.role),
    );

    // Default to athlete view while role is loading. Same rationale as
    // [HomeScreen]: athletes dominate; rendering early avoids skeleton stalls.
    return role == UserRole.trainer
        ? const TrainerWorkoutView()
        : _AthleteWorkout(initialTab: initialTab);
  }
}

/// Athlete workout — fixed 2-page [DefaultTabController] + swipeable
/// [TabBarView] (same structure the rankings-era tab used). BOTH pages keep
/// their provider subscriptions alive via [AutomaticKeepAliveClientMixin]
/// while swiped away — swapping tabs must not tear down streams (the coach
/// cards would pop in late on every visit). Everything (autoDispose chains
/// included) is released together when the athlete leaves the `/workout`
/// route, matching the lifetime the old single-page sections had.
class _AthleteWorkout extends StatelessWidget {
  const _AthleteWorkout({this.initialTab});

  final String? initialTab;

  static const _labels = <String>['TU ENTRENO', 'PLANTILLAS'];

  /// Slugs de analytics — estables, en el orden del [TabBarView]. No son los
  /// labels: esos cambian con el copy y con el idioma. Y "PLANTILLAS" además
  /// está en discusión en #638, así que atarse al texto sería atarse a algo
  /// que ya se sabe que va a cambiar.
  static const _analyticsSurface = 'workout';
  static const _analyticsTabs = <String>['tu-entreno', 'plantillas'];

  static int _resolveInitialIndex(String? tab) => tab == 'plantillas' ? 1 : 0;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final labelStyle = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
    );
    final scaledLabelHeight = textScaler.scale(labelStyle?.fontSize ?? 14) *
        (labelStyle?.height ?? 1.2);
    final tabHeight =
        scaledLabelHeight + 20 < 40 ? 40.0 : scaledLabelHeight + 20;
    final scrollTabs = textScaler.scale(1) > 1.3;

    return DefaultTabController(
      length: _labels.length,
      initialIndex: _resolveInitialIndex(initialTab),
      child: Column(
        children: [
          // Segmented pill control — mirrors TrainerCoachView's sub-tab
          // language (week tabs, bottom-bar pill).
          Container(
            margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: palette.bgCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: palette.textMuted.withValues(alpha: 0.12),
              ),
            ),
            child: TabBar(
              isScrollable: scrollTabs,
              tabAlignment: scrollTabs ? TabAlignment.start : TabAlignment.fill,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: palette.accent,
                borderRadius: BorderRadius.circular(20),
              ),
              splashBorderRadius: BorderRadius.circular(20),
              labelColor: palette.bg,
              unselectedLabelColor: palette.textMuted,
              labelStyle: labelStyle,
              tabs: [
                for (final label in _labels)
                  Tab(
                    height: tabHeight,
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // TU ENTRENO y PLANTILLAS son las dos la ruta `/workout`: mismo
          // punto ciego que Feed. Envuelve las PÁGINAS, no el pill.
          const Expanded(
            child: SubTabAnalytics(
              surface: _analyticsSurface,
              tabs: _analyticsTabs,
              child: TabBarView(
                // Swipeable on purpose — same gesture language the tab had in
                // the rankings era.
                children: [_TuEntrenoPage(), PlantillasTab()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Page 0 — unified RUTINAS list (workout redesign slice 1: former "Mi plan"
/// + "Mis rutinas" merged, coach plans pinned with their own chip) + session
/// history. Wrapped with [AutomaticKeepAliveClientMixin] so its section
/// providers are NOT rebuilt when swiping to PLANTILLAS and back.
class _TuEntrenoPage extends StatefulWidget {
  const _TuEntrenoPage();

  @override
  State<_TuEntrenoPage> createState() => _TuEntrenoPageState();
}

class _TuEntrenoPageState extends State<_TuEntrenoPage>
    with AutomaticKeepAliveClientMixin<_TuEntrenoPage> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      // SingleChildScrollView + Column (no ListView(children:)): un ListView,
      // aunque construya sus widgets eager, sigue siendo un viewport — los
      // Elements/State de los TreinoFadeSlideIn que salen del cacheExtent se
      // desmontan y re-animan al volver a scrollear. Column dentro de
      // SingleChildScrollView scrollea como una sola unidad, sin reciclar
      // Elements por ítem (ver doc de TreinoFadeSlideIn).
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
              child: const RutinasSection(),
            ),
            const SizedBox(height: 12),
            TreinoFadeSlideIn(
              delay: AppMotion.stagger(1),
              child: const HistorialSection(),
            ),
          ],
        ),
      ),
    );
  }
}
