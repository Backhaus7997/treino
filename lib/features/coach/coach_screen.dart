import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/motion/treino_state_switcher.dart';
import '../profile/application/user_providers.dart';
import '../profile/domain/user_role.dart';
import 'athlete_coach_view.dart';
import 'trainer_coach_view.dart';

class CoachScreen extends ConsumerWidget {
  const CoachScreen({super.key, this.initialTab});

  /// Optional initial sub-tab for the trainer view, sourced from go_router's
  /// `?tab=` query param. See [TrainerCoachView.initialTab] for accepted
  /// values. Ignored for the athlete view.
  final String? initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Granular: rebuild ONLY when role identity changes. select() over
    // AsyncValue<UserProfile?> projects to UserRole? — null while loading,
    // null on error (provider collapses error to value(null)), or the role
    // when the doc resolves.
    final UserRole? role = ref.watch(
      userProfileProvider.select((async) => async.valueOrNull?.role),
    );

    return TreinoStateSwitcher(
      childKey: ValueKey(role?.name ?? 'loading'),
      child: switch (role) {
        UserRole.athlete => const AthleteCoachView(),
        UserRole.trainer => TrainerCoachView(initialTab: initialTab),
        null => const _CoachLoadingView(),
      },
    );
  }
}

class _CoachLoadingView extends StatelessWidget {
  const _CoachLoadingView();

  @override
  Widget build(BuildContext context) {
    // Neutral background, no spinner. Per ADR-3: do NOT block
    // the entire tab on a CircularProgressIndicator — that degrades UX for
    // athletes whose profile is already cached. Empty colored surface is
    // imperceptible on warm cache and tolerable on cold cache.
    return const SizedBox.expand();
  }
}
