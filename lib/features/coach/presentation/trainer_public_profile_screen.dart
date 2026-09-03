import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/tokens/tokens.dart' show AppSpacing;
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../reviews/presentation/widgets/review_cta.dart';
import '../../reviews/presentation/widgets/trainer_reviews_section.dart';
import '../application/trainer_discovery_providers.dart';
import '../../coach_hub/presentation/sections/pagos/widgets/payment_format.dart'
    show fmtArs;
import 'widgets/trainer_contact_cta_stub.dart';
import 'widgets/trainer_inquiry_cta.dart';
import 'widgets/trainer_profile_hero.dart';
import 'widgets/trainer_stats_row.dart';

/// Perfil público de un entrenador.
///
/// Bajo ShellRoute per D17 (con bottom bar visible).
///
/// Dos CTAs desde #637, en este orden: **CONSULTAR** (primario, abre un chat
/// de pre-consulta sin vínculo formal) y **PEDIR VÍNCULO** (secundario, el
/// compromiso explícito). Ver [TrainerInquiryCta] para el porqué de la
/// jerarquía.
class TrainerPublicProfileScreen extends ConsumerWidget {
  const TrainerPublicProfileScreen({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
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
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              8 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              TrainerProfileHero(profile: profile),
              const SizedBox(height: 24),
              TrainerStatsRow(profile: profile),
              const SizedBox(height: 24),
              Text(
                profile.trainerBio?.isNotEmpty == true
                    ? profile.trainerBio!
                    : l10n.coachProfileBioEmpty,
                style: TextStyle(color: palette.textPrimary, fontSize: 14),
              ),
              const SizedBox(height: 16),
              if (profile.trainerMonthlyRate != null)
                Row(
                  children: [
                    Text(
                      l10n.coachProfileRateLabel,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${fmtArs(profile.trainerMonthlyRate!)}${l10n.coachMonthlyRateUnit}',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 24),
              // #637 — ORDEN DELIBERADO, es la decisión de producto del issue.
              //
              // Consultar va PRIMERO y lleno: es el paso liviano, el que no
              // compromete a nada y el que los entrevistados pedían poder dar
              // antes de decidir. Pedir vínculo va debajo y contorneado: sigue
              // estando a un toque, pero deja de ser el único camino y pasa a
              // ser lo que siempre fue en realidad, el compromiso explícito.
              //
              // Antes, con un solo CTA, "PEDIR VÍNCULO" era primario por
              // inercia — y el efecto era que preguntarle algo a un entrenador
              // exigía elegirlo primero.
              TrainerInquiryCta(trainerId: uid),
              const SizedBox(height: AppSpacing.s12),
              TrainerContactCtaStub(trainerId: uid),
              const SizedBox(height: 12),
              ReviewCta(trainerId: uid),
              const SizedBox(height: 20),
              TrainerReviewsSection(trainerId: uid),
              const SizedBox(height: 20),
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
    final l10n = AppL10n.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.coachProfileNotFoundLabel,
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
    final l10n = AppL10n.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.coachProfileErrorLabel,
              style: TextStyle(color: palette.textMuted),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              child: Text(l10n.coachRetryLabel),
            ),
          ],
        ),
      ),
    );
  }
}
