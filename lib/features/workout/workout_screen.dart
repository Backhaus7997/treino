import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_palette.dart';
import '../gym_rankings/presentation/rankings_screen.dart' show RankingsBody;
import '../profile/application/user_providers.dart';
import '../profile/domain/user_role.dart';
import 'presentation/widgets/historial_section.dart';
import 'presentation/widgets/mi_plan_section.dart';
import 'presentation/widgets/mis_rutinas_section.dart';
import 'presentation/widgets/plantillas_section.dart';
import 'presentation/widgets/trainer_templates_section.dart';
import 'trainer_workout_view.dart';

/// Role-aware workout screen.
///
/// - Athlete → 2-page swipeable Entrenar tab: "Tu entreno" (page 0, existing
///   body) + "Rankings" (page 1, relocated from `/profile/rankings` — spec
///   `gym-rankings` — Rankings Placement, design `sdd/rankings-v2/design`
///   AD-1/AD-2).
/// - Trainer → [TrainerWorkoutView] dedicated to plan creation. Trainers
///   should not see athlete-mode controls (no EMPEZAR, no historial propio,
///   no rankings page); their WORKOUT surface is exclusively for assigning
///   routines.
/// - Loading → empty surface (matches [HomeScreen] / [CoachScreen] pattern).
class WorkoutScreen extends ConsumerWidget {
  const WorkoutScreen({super.key, this.initialTab});

  /// Optional initial sub-tab — accepts `'rankings'`. Read from the
  /// `?tab=` query param by the `/workout` route builder (design AD-2,
  /// mirrors `CoachScreen.initialTab` → `TrainerCoachView`). Ignored for the
  /// trainer view.
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
/// [TabBarView] (design AD-1). ALL state-branching (loading/no-gym/opted-out/
/// leaderboards) lives INSIDE page 1 (`_RankingsPage`) — the child list
/// itself never branches, so page identity/order never changes across
/// rebuilds. Page 0 keeps its provider subscriptions alive via
/// [AutomaticKeepAliveClientMixin] while swiped away; page 1's Firestore
/// leaderboard listeners are `autoDispose` and release on swipe-away.
class _AthleteWorkout extends StatelessWidget {
  const _AthleteWorkout({this.initialTab});

  final String? initialTab;

  static const _labels = <String>['TU ENTRENO', 'RANKINGS'];

  static int _resolveInitialIndex(String? tab) => tab == 'rankings' ? 1 : 0;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

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
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: palette.accent,
                borderRadius: BorderRadius.circular(20),
              ),
              splashBorderRadius: BorderRadius.circular(20),
              labelColor: palette.bg,
              unselectedLabelColor: palette.textMuted,
              labelStyle: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
              tabs: [
                for (final l in _labels) Tab(text: l, height: 40),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Expanded(
            child: TabBarView(
              // Swipeable per spec `gym-rankings` — Rankings Placement
              // ("reachable by horizontal swipe and/or a top tab control").
              children: [
                _TuEntrenoPage(),
                _RankingsPage(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Page 0 — original [WorkoutScreen] body extracted intact, now wrapped with
/// [AutomaticKeepAliveClientMixin] so its section providers (MiPlan/
/// TrainerTemplates/MisRutinas/Plantillas/Historial) are NOT rebuilt when
/// swiping to page 1 and back (design AD-1 rebuild-safety).
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
      child: ListView(
        // + bottom inset: the floating bar overlays the body (extendBody),
        // so the last item needs room to scroll out from behind it.
        padding: EdgeInsets.fromLTRB(
            0, 20, 0, 20 + MediaQuery.paddingOf(context).bottom),
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          MiPlanSection(),
          SizedBox(height: 12),
          // Trainer-shared templates surface — invisible if the athlete has
          // no active link or the trainer hasn't opted in. Sits between
          // "Mi plan" (their assigned routine) and "Plantillas" (catalog)
          // because conceptually it's still "stuff your trainer made for
          // you", just non-assigned.
          TrainerTemplatesSection(),
          SizedBox(height: 12),
          // Athlete-authored routines (athlete-self-routines SDD).
          // Belongs after TrainerTemplates because both are "my plans"
          // (trainer-sourced first, then self-made), then the public
          // catalog Plantillas, then Historial.
          MisRutinasSection(),
          SizedBox(height: 12),
          PlantillasSection(),
          SizedBox(height: 12),
          HistorialSection(),
        ],
      ),
    );
  }
}

/// Page 1 — thin host that composes the Phase 1 gating wrapper
/// ([RankingsBody], relocated from `RankingsScreen`) — a self-contained
/// widget that owns its own header (design AD-7: slim `RANKINGS` title +
/// disable affordance, replacing the old back-button header now that this
/// is a tab page, not a pushed route) and all state-branching (no-gym /
/// opted-out / leaderboards). NOT kept alive — its leaderboard listeners are
/// `autoDispose` and release on swipe-away (design AD-1).
class _RankingsPage extends StatelessWidget {
  const _RankingsPage();

  @override
  Widget build(BuildContext context) {
    return const RankingsBody();
  }
}
