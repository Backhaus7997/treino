import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/tokens/tokens.dart' show AppSpacing;
import '../../../core/widgets/treino_collapsing_top_bar.dart';
import '../../../l10n/app_l10n.dart';
import '../../reviews/presentation/widgets/review_cta.dart';
import '../../reviews/presentation/widgets/trainer_reviews_section.dart';
import '../application/trainer_discovery_providers.dart';
import '../domain/trainer_public_profile.dart';
import '../../coach_hub/presentation/sections/pagos/widgets/payment_format.dart'
    show fmtArs;
import 'widgets/trainer_contact_cta_stub.dart';
import 'widgets/trainer_inquiry_cta.dart';
import 'widgets/trainer_preview_notices.dart';
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
///
/// Con [preview] la abre el PROPIO PF desde VER PREVIEW (#1498): se ve igual
/// que para un alumno, pero marcada como vista previa, con los dos CTAs
/// deshabilitados (ninguno actúa sobre uno mismo) y, si le falta, un aviso de
/// que no cargó sus años de experiencia.
class TrainerPublicProfileScreen extends ConsumerWidget {
  const TrainerPublicProfileScreen({
    super.key,
    required this.uid,
    this.preview = false,
  });

  final String uid;

  /// `true` = el PF mirando su propio perfil. Ver el dartdoc de la clase.
  final bool preview;

  /// A dónde cae «atrás» cuando no hay nada que popear (deep link). La vista
  /// previa nace en PERFIL, no en Coach.
  String get _fallbackPath => preview ? '/profile' : '/coach';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    // Vista previa del PF: perfil EN VIVO, para que el guardado se vea sin
    // reiniciar (#1498). Un alumno mira un perfil ajeno con la lectura puntual
    // de siempre. `preview` es final: la rama no cambia en la vida del widget.
    final AsyncValue<TrainerPublicProfile?> async = preview
        ? ref.watch(trainerLiveByIdProvider(uid))
        : ref.watch(trainerByIdProvider(uid));

    // #1559: barra que aparece al scrollear, como el resto de los detalles.
    // Antes era un AppBar transparente, y Material 3 le pintaba una banda
    // (scrolled-under) que cortaba el avatar.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: TreinoCollapsingTopBar(
        title: async.valueOrNull?.displayName,
        // El nombre grande del hero sale de pantalla ~200 px abajo.
        collapseOffset: 200,
        onBack: () =>
            context.canPop() ? context.pop() : context.go(_fallbackPath),
        body: async.when(
          loading: () => Center(
            child: CircularProgressIndicator(color: palette.accent),
          ),
          error: (_, __) => _ErrorState(
            onRetry: () => preview
                ? ref.invalidate(trainerLiveByIdProvider(uid))
                : ref.invalidate(trainerByIdProvider(uid)),
          ),
          data: (profile) {
            if (profile == null) {
              return _NotFoundState(fallbackPath: _fallbackPath);
            }
            return ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                TreinoTopBarMetrics.reservedHeightOf(context),
                20,
                8 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                if (preview) ...[
                  const TrainerPreviewBanner(),
                  const SizedBox(height: AppSpacing.s8),
                ],
                TrainerProfileHero(profile: profile),
                const SizedBox(height: 24),
                TrainerStatsRow(profile: profile),
                if (preview && profile.trainerExperienceYears == null) ...[
                  const SizedBox(height: AppSpacing.s12),
                  const TrainerPreviewMissingExperienceNotice(),
                ],
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
                // #637 — el kill switch del PF, del lado que lo ve el alumno.
                // Sin esto, apagar las consultas dejaba el botón puesto y la
                // regla rebotaba la creación del chat: el alumno se comía un
                // error por una decisión deliberada del PF. Se lee del perfil
                // que esta pantalla YA tiene en mano, así que el CTA conserva su
                // propiedad de no watchear ningún provider.
                //
                // La pausa del PF (`acceptingAthletes`) también cierra las
                // consultas — la rule las rechaza —, así que se esconde igual.
                // El de vínculo NO se esconde: lo decide el propio CTA, que es
                // el que le muestra al alumno actual su vínculo con este PF.
                if (profile.acceptsInquiries && profile.acceptingAthletes) ...[
                  TrainerInquiryCta(trainerId: uid, preview: preview),
                  const SizedBox(height: AppSpacing.s12),
                ],
                TrainerContactCtaStub(
                  trainerId: uid,
                  preview: preview,
                  acceptingAthletes: profile.acceptingAthletes,
                  trainerName: profile.displayName,
                ),
                const SizedBox(height: 12),
                ReviewCta(trainerId: uid),
                const SizedBox(height: 20),
                TrainerReviewsSection(trainerId: uid),
                const SizedBox(height: 20),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NotFoundState extends StatelessWidget {
  const _NotFoundState({required this.fallbackPath});

  final String fallbackPath;

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
              onPressed: () => GoRouter.of(context).go(fallbackPath),
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
