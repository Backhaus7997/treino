import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_motion.dart';
import '../../core/widgets/motion/treino_fade_slide_in.dart';
import '../profile/application/user_providers.dart';
import '../profile/domain/user_role.dart';
import 'presentation/widgets/historial_section.dart';
import 'presentation/widgets/plantillas_section.dart';
import 'presentation/widgets/rutinas_section.dart';
import 'presentation/widgets/trainer_templates_section.dart';
import 'trainer_workout_view.dart';

/// Role-aware workout screen.
///
/// - Athlete → single "Tu entreno" body. Rankings, formerly the second page
///   of this tab (rankings-v2), relocated to the FEED tab
///   (`/feed?tab=rankings`) — see [FeedScreen].
/// - Trainer → [TrainerWorkoutView] dedicated to plan creation. Trainers
///   should not see athlete-mode controls (no EMPEZAR, no historial propio);
///   their WORKOUT surface is exclusively for assigning routines.
/// - Loading → empty surface (matches [HomeScreen] / [CoachScreen] pattern).
class WorkoutScreen extends ConsumerWidget {
  const WorkoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserRole? role = ref.watch(
      userProfileProvider.select((async) => async.valueOrNull?.role),
    );

    // Default to athlete view while role is loading. Same rationale as
    // [HomeScreen]: athletes dominate; rendering early avoids skeleton stalls.
    return role == UserRole.trainer
        ? const TrainerWorkoutView()
        : const _AthleteWorkout();
  }
}

/// Athlete workout body — unified routines list (coach plans pinned + own),
/// trainer templates, public catalog, and session history.
class _AthleteWorkout extends StatelessWidget {
  const _AthleteWorkout();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ListView(
        // + bottom inset: the floating bar overlays the body (extendBody),
        // so the last item needs room to scroll out from behind it.
        padding: EdgeInsets.fromLTRB(
          0,
          20,
          0,
          20 + MediaQuery.paddingOf(context).bottom,
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // Unified RUTINAS list (workout-area redesign slice 1): merges the
          // former "Mi plan" (trainer-assigned) + "Mis rutinas" (self-made)
          // sections — coach plans pinned on top with their own chip.
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(0),
            child: const RutinasSection(),
          ),
          const SizedBox(height: 12),
          // Trainer-shared templates surface — invisible if the athlete has
          // no active link or the trainer hasn't opted in. Sits between the
          // unified routines list and "Plantillas" (catalog) because
          // conceptually it's still "stuff your trainer made for you", just
          // non-assigned.
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(1),
            child: const TrainerTemplatesSection(),
          ),
          const SizedBox(height: 12),
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(2),
            child: const PlantillasSection(),
          ),
          const SizedBox(height: 12),
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(3),
            child: const HistorialSection(),
          ),
        ],
      ),
    );
  }
}
