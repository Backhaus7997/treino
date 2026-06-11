import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
/// - Athlete → existing body (Mi plan / Plantillas / Historial).
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

/// Athlete workout — original [WorkoutScreen] body extracted intact.
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
            0, 20, 0, 20 + MediaQuery.paddingOf(context).bottom),
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          MiPlanSection(),
          SizedBox(height: 20),
          // Trainer-shared templates surface — invisible if the athlete has
          // no active link or the trainer hasn't opted in. Sits between
          // "Mi plan" (their assigned routine) and "Plantillas" (catalog)
          // because conceptually it's still "stuff your trainer made for
          // you", just non-assigned.
          TrainerTemplatesSection(),
          SizedBox(height: 20),
          // Athlete-authored routines (athlete-self-routines SDD).
          // Belongs after TrainerTemplates because both are "my plans"
          // (trainer-sourced first, then self-made), then the public
          // catalog Plantillas, then Historial.
          MisRutinasSection(),
          SizedBox(height: 20),
          PlantillasSection(),
          SizedBox(height: 20),
          HistorialSection(),
        ],
      ),
    );
  }
}
