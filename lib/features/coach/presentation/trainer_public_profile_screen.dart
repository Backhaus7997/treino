import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../application/trainer_discovery_providers.dart';
import 'coach_strings.dart';
import 'widgets/trainer_contact_cta_stub.dart';
import 'widgets/trainer_profile_hero.dart';
import 'widgets/trainer_stats_row.dart';

/// Perfil público de un entrenador.
///
/// Bajo ShellRoute per D17 (con bottom bar visible). CTA "PEDIR VÍNCULO"
/// es stub esta etapa (Etapa 3 implementa el real).
class TrainerPublicProfileScreen extends ConsumerWidget {
  const TrainerPublicProfileScreen({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final async = ref.watch(trainerByIdProvider(uid));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(TreinoIcon.back, color: palette.textPrimary),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/coach'),
        ),
      ),
      body: async.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: palette.accent),
        ),
        error: (_, __) => _ErrorState(
          onRetry: () => ref.invalidate(trainerByIdProvider(uid)),
        ),
        data: (profile) {
          if (profile == null) {
            return _NotFoundState();
          }
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            children: [
              TrainerProfileHero(profile: profile),
              const SizedBox(height: 24),
              const TrainerStatsRow(),
              const SizedBox(height: 24),
              Text(
                profile.trainerBio?.isNotEmpty == true
                    ? profile.trainerBio!
                    : CoachStrings.profileBioEmpty,
                style: TextStyle(color: palette.textPrimary, fontSize: 14),
              ),
              const SizedBox(height: 16),
              if (profile.trainerHourlyRate != null)
                Row(
                  children: [
                    Text(
                      CoachStrings.profileRateLabel,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '\$${profile.trainerHourlyRate}${CoachStrings.hourlyRateUnit}',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 24),
              const TrainerContactCtaStub(),
            ],
          );
        },
      ),
    );
  }
}

class _NotFoundState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              CoachStrings.profileNotFoundLabel,
              style: TextStyle(color: palette.textMuted),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => GoRouter.of(context).go('/coach'),
              child: const Text('Volver'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              CoachStrings.profileErrorLabel,
              style: TextStyle(color: palette.textMuted),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              child: const Text(CoachStrings.retryLabel),
            ),
          ],
        ),
      ),
    );
  }
}
