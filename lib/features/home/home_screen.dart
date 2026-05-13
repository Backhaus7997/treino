import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../profile/application/user_providers.dart';
import 'widgets/empezar_entrenamiento_card.dart';
import 'widgets/esta_semana_card.dart';
import 'widgets/home_header.dart';

/// Home screen — single ConsumerWidget that owns the one ref.watch call
/// (REQ-HOME-SCREEN-001). No Scaffold, AppBackground, or SafeArea — those
/// are provided by _ShellScaffold in router.dart (REQ-HOME-SCREEN-002).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);

    final Widget headerOrSkeleton = profileAsync.when(
      data: (profile) => HomeHeader(profile: profile),
      loading: () => const _HomeHeaderSkeleton(),
      error: (_, __) => const HomeHeader(profile: null),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        physics: const ClampingScrollPhysics(),
        children: [
          headerOrSkeleton,
          const SizedBox(height: 20),
          const EmpezarEntrenamientoCard(),
          const SizedBox(height: 12),
          const EstaSemanaCard(),
        ],
      ),
    );
  }
}

/// Private placeholder that occupies the same 56 px height as [HomeHeader]
/// during [AsyncLoading], preventing a layout jump (REQ-HOME-PROVIDER-003).
/// Not animated — a real shimmer can replace this single widget in a future PR.
/// Lives here (not in home_header.dart) because it couples to the loading
/// branch of [userProfileProvider], not to [HomeHeader]'s internal logic
/// (ADR-HS-9).
class _HomeHeaderSkeleton extends StatelessWidget {
  const _HomeHeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 56);
  }
}
