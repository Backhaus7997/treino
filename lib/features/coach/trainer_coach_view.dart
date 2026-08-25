import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../app/theme/app_palette.dart';
import '../../core/widgets/motion/treino_state_switcher.dart';
import '../../core/widgets/treino_icon.dart';
import '../chat/application/chat_providers.dart';
import '../coach_hub/presentation/sections/facturacion_planes/plan_limit_paywall.dart';
import '../profile/application/user_providers.dart';
import '../profile/application/user_public_profile_providers.dart';
import '../profile/domain/user_public_profile.dart';
import '../workout/application/session_providers.dart' show currentUidProvider;
import 'application/trainer_link_providers.dart';
import 'data/trainer_link_promotion_service.dart';
import 'domain/subscription_tier.dart';
import 'domain/trainer_link.dart';
import 'domain/trainer_link_entitlement.dart';
import 'domain/trainer_link_status.dart';
import 'domain/weighted_load.dart';
import 'presentation/trainer_agenda_tab.dart';
import '../../core/widgets/treino_segmented_pill.dart';

class TrainerCoachView extends StatelessWidget {
  const TrainerCoachView({super.key, this.initialTab});

  /// Optional initial sub-tab — accepts `'alumnos'` or `'agenda'`.
  /// Read from the `?tab=` query param by [CoachScreen]
  /// so deep links from the trainer dashboard land on the right tab.
  final String? initialTab;

  static const _labels = <String>['ALUMNOS', 'AGENDA'];

  static int _resolveInitialIndex(String? tab) {
    switch (tab) {
      case 'agenda':
        return 1;
      case 'alumnos':
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _labels.length,
      initialIndex: _resolveInitialIndex(initialTab),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: TreinoSegmentedPill(
              labels: _labels,
              // Close any open popup (e.g. agenda day sheet) when the trainer
              // switches sub-tabs. Pop both navigators because showModalBottomSheet
              // defaults to useRootNavigator: false (local navigator).
              onTap: (_) {
                Navigator.of(context).popUntil((route) => route is! PopupRoute);
                Navigator.of(
                  context,
                  rootNavigator: true,
                ).popUntil((route) => route is! PopupRoute);
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                const _AlumnosTab(),
                Consumer(
                  builder: (context, ref, _) {
                    final uid = ref.watch(currentUidProvider) ?? '';
                    return TrainerAgendaTab(trainerId: uid);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── ALUMNOS tab ───────────────────────────────────────────────────────────────

class _AlumnosTab extends ConsumerWidget {
  const _AlumnosTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final linksAsync = ref.watch(trainerLinksStreamProvider);

    return TreinoStateSwitcher(
      childKey: ValueKey(
        linksAsync.when(
          data: (_) => 'data',
          loading: () => 'loading',
          error: (_, __) => 'error',
        ),
      ),
      child: linksAsync.when(
        loading: () =>
            Center(child: CircularProgressIndicator(color: palette.accent)),
        error: (_, __) => Center(
          child: Text(
            'No pudimos cargar tus alumnos.',
            style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
          ),
        ),
        data: (links) {
          final visible = links
              .where(
                (l) =>
                    l.status == TrainerLinkStatus.active ||
                    l.status == TrainerLinkStatus.paused,
              )
              .toList();
          // El medidor de cupo va ARRIBA de la lista y TAMBIÉN sobre el empty
          // state: el PF tiene que ver cuánto le queda ANTES de chocar con el
          // tope, no cuando el gate ya le rebotó un alta. Se alimenta de
          // `links` crudos, no de `visible`: computeWeightedLoad tiene sus
          // propias reglas (dedup por atleta, excluye blocked, pending pesa 0).
          return Column(
            children: [
              _PlanQuotaHeader(links: links),
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                TreinoIcon.users,
                                size: 48,
                                color: palette.textMuted,
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Sin alumnos activos todavía.',
                                style: GoogleFonts.barlow(
                                  fontWeight: FontWeight.w400,
                                  fontSize: 14,
                                  color: palette.textMuted,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        // Bottom inset clears the shell's floating nav bar
                        // (extendBody:true).
                        padding: EdgeInsets.fromLTRB(
                          20,
                          12,
                          20,
                          20 + MediaQuery.paddingOf(context).bottom,
                        ),
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) =>
                            _ActiveAlumnoCard(link: visible[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Plan quota header ─────────────────────────────────────────────────────────

/// Medidor de cupo del plan, arriba del roster móvil (paywall Fase 7).
///
/// «2 DE 2 · PLAN FREE». El punto es que el PF VEA VENIR el tope: hasta ahora
/// se enteraba del límite recién cuando el gate le rebotaba un alta, y ahí ya
/// era tarde (el alumno quedó afuera y hay que explicárselo).
class _PlanQuotaHeader extends ConsumerWidget {
  const _PlanQuotaHeader({required this.links});

  /// Vínculos CRUDOS del PF — [computeWeightedLoad] filtra y deduplica solo.
  final List<TrainerLink> links;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final sub = ref.watch(userProfileProvider).valueOrNull?.subscription;
    // Sin `subscription` en el doc → Free: un PF sin suscripción es Free por
    // definición (no hay backfill).
    final tier = sub?.tier ?? SubscriptionTier.free;
    // El TIER decide si hay tope, NO el `weightLimit` denormalizado. Si el CF
    // dejó un weightLimit viejo en un doc que ya es plan3, leerlo de ahí
    // volvería a meter un denominador en el plan ilimitado. `isUnlimited` sale
    // de kTierWeightLimits, la fuente de verdad client-side.
    final limit =
        tier.isUnlimited ? null : (sub?.weightLimit ?? tier.weightLimit);

    // Carga PONDERADA: activo 1.0, pausado 0.5. Por eso el contador puede dar
    // 1.5 y no es un error de redondeo.
    final load = computeWeightedLoad(links);
    // El igual cuenta como «al límite»: con load == limit ya no entra nadie
    // más, y ese es justo el momento en que el aviso sirve.
    final atLimit = limit != null && load >= limit;

    // Plan sin tope: NUNCA imprimas denominador. Interpolar un `limit` nulo
    // acá renderiza el string "null" — ya pasó en producción. El singular sale
    // solo en el 1 exacto: 0.5 y 1.5 van en plural, como en castellano.
    final label = limit == null
        ? '${formatWeightedLoad(load)} ${load == 1 ? 'ALUMNO' : 'ALUMNOS'} '
            '· ${_tierLabel(tier)}'
        : '${formatWeightedLoad(load)} DE $limit · ${_tierLabel(tier)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          Icon(
            TreinoIcon.users,
            size: 14,
            color: atLimit ? palette.highlight : palette.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label, // i18n: Fase W3
              key: const Key('plan-quota-header'),
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.8,
                color: atLimit ? palette.highlight : palette.textMuted,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Nombre del tier dentro del medidor — UPPERCASE, es un eyebrow.
String _tierLabel(SubscriptionTier tier) => switch (tier) {
      SubscriptionTier.free => 'PLAN FREE', // i18n: Fase W3
      SubscriptionTier.plan1 => 'PLAN 1', // i18n: Fase W3
      SubscriptionTier.plan2 => 'PLAN 2', // i18n: Fase W3
      SubscriptionTier.plan3 => 'PLAN 3', // i18n: Fase W3
    };

// ── Active alumno card ────────────────────────────────────────────────────────

class _ActiveAlumnoCard extends ConsumerWidget {
  const _ActiveAlumnoCard({required this.link});
  final TrainerLink link;

  Future<void> _confirmAndRun(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String body,
    required String confirmLabel,
    required Color confirmBg,
    required Future<void> Function() action,
    // Optional hook so callers with a richer error contract (e.g. resume's
    // LinkPromotionFailure — plan-limit paywall vs. two snackbar variants)
    // can render their own feedback instead of the generic snackbar below.
    // NOT typed to LinkPromotionFailure: the catch below stays catch-all
    // (QA H5 / see comment on the try/catch) and hands whatever it caught to
    // this hook, which is responsible for its own default branch.
    Future<void> Function(BuildContext context, Object error)? onFailure,
  }) async {
    final palette = AppPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text(
          title,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: palette.textPrimary,
          ),
        ),
        content: Text(
          body,
          style: GoogleFonts.barlow(fontSize: 14, color: palette.textPrimary),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: palette.textPrimary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmBg,
              foregroundColor: palette.bg,
            ),
            child: Text(
              confirmLabel,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // try/catch obligatorio (QA C1-siblings, hallazgo H5): sin él, si
    // pause/resume/terminate lanza (permission-denied de App Check, rules, o
    // cualquier FirebaseException) la excepción escapa como async no capturada,
    // cae en runZonedGuarded y se registra en Crashlytics como error FATAL, y
    // el PF no recibe ningún feedback: el diálogo ya se cerró y la card no
    // cambia. Ahora falla con un SnackBar y sin fatal.
    try {
      await action();
    } catch (e) {
      if (!context.mounted) return;
      if (onFailure != null) {
        await onFailure(context, e);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pudimos actualizar el vínculo. Probá de nuevo.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final pubAsync = ref.watch(userPublicProfileProvider(link.athleteId));
    final isPaused = link.status == TrainerLinkStatus.paused;
    // Bloqueado por el limite del plan del PF (paywall Fase 7). MANDA sobre
    // pausado: es lo unico accionable, y lo unico que explica por que este
    // alumno no cuenta. El ALUMNO no pierde nada — conserva rutinas,
    // historial y chat; el que tiene que regularizar es el PF.
    final isBlocked = link.entitlement == TrainerLinkEntitlement.blocked;
    final hasUnread = ref.watch(hasUnreadFromProvider(link.athleteId));

    return InkWell(
      onTap: () => context.push('/coach/athlete/${link.athleteId}'),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: palette.border, width: 1),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _UserHeader(
              pubAsync: pubAsync,
              subtitle: isBlocked
                  ? 'Bloqueado por el límite de tu plan' // i18n: Fase W3
                  : isPaused
                      ? 'Vínculo pausado · ${_formatAcceptedAt(link)}'
                      : 'Vinculado desde ${_formatAcceptedAt(link)}',
              statusBadge: isBlocked
                  ? _StatusBadge(
                      label: 'BLOQUEADO', // i18n: Fase W3
                      color: palette.highlight,
                    )
                  : isPaused
                      ? _StatusBadge(
                          label: 'PAUSADO',
                          color: palette.textMuted,
                        )
                      : null,
              hasUnread: hasUnread,
              unreadDotKey: Key('unread-dot-${link.athleteId}'),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: isPaused
                  ? ElevatedButton(
                      onPressed: () => _confirmAndRun(
                        context,
                        ref,
                        title: 'Reanudar vínculo',
                        body:
                            '¿Querés reanudar el vínculo con este alumno? Va a poder ver tus updates de nuevo.',
                        confirmLabel: 'Reanudar',
                        confirmBg: palette.accent,
                        action: () => ref
                            .read(trainerLinkPromotionServiceProvider)
                            .resume(link.id),
                        onFailure: (context, error) async {
                          if (error is LinkPromotionFailure$PlanLimitReached) {
                            await showPlanLimitPaywall(
                              context,
                              currentTier: error.tier,
                              reason: error.reason == 'subscription-inactive'
                                  ? PlanLimitReason.subscriptionInactive
                                  : PlanLimitReason.planLimit,
                            );
                            return;
                          }
                          if (!context.mounted) return;
                          if (error
                              is LinkPromotionFailure$PromotionPrecondition) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Este vínculo ya no está disponible.',
                                ),
                              ),
                            );
                            return;
                          }
                          // Catch-all (QA H5 — deliberately NOT narrowed to
                          // LinkPromotionFailure): anything outside the
                          // sealed hierarchy — a service bug, a platform
                          // error — must still surface feedback instead of
                          // leaving the trainer believing nothing happened.
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Revisá tu conexión y probá de nuevo.',
                              ),
                            ),
                          );
                        },
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: palette.accent,
                        foregroundColor: TreinoButtonTokens.foreground(context),
                        minimumSize: const Size.fromHeight(40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                      ),
                      child: Text(
                        'REANUDAR VÍNCULO',
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.8,
                        ),
                      ),
                    )
                  : OutlinedButton(
                      onPressed: () => _confirmAndRun(
                        context,
                        ref,
                        title: 'Pausar vínculo',
                        body:
                            '¿Querés pausar el vínculo con este alumno? Va a quedar en read-only hasta que reanudes.',
                        confirmLabel: 'Pausar',
                        confirmBg: palette.accent,
                        action: () => ref
                            .read(trainerLinkRepositoryProvider)
                            .pause(link.id),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: palette.accent, width: 1),
                        foregroundColor: palette.accent,
                        minimumSize: const Size.fromHeight(40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                      ),
                      child: Text(
                        'PAUSAR VÍNCULO',
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _confirmAndRun(
                  context,
                  ref,
                  title: 'Terminar vínculo',
                  body:
                      '¿Seguro que querés terminar el vínculo con este alumno?',
                  confirmLabel: 'Terminar',
                  confirmBg: palette.highlight,
                  action: () => ref
                      .read(trainerLinkRepositoryProvider)
                      .terminate(link.id, reason: 'trainer-terminated'),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: palette.border, width: 1),
                  foregroundColor: palette.textMuted,
                  minimumSize: const Size.fromHeight(40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
                child: Text(
                  'TERMINAR VÍNCULO',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatAcceptedAt(TrainerLink l) {
    final dt = (l.acceptedAt ?? l.requestedAt).toLocal();
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    return '$dd/$mm/${dt.year}';
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _UserHeader extends StatelessWidget {
  const _UserHeader({
    required this.pubAsync,
    required this.subtitle,
    this.statusBadge,
    this.hasUnread = false,
    this.unreadDotKey,
  });
  final AsyncValue<UserPublicProfile?> pubAsync;
  final String subtitle;
  final Widget? statusBadge;
  final bool hasUnread;
  final Key? unreadDotKey;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final name = pubAsync.valueOrNull?.displayName ?? '...';

    return Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.bg,
                border: Border.all(color: palette.border, width: 1),
              ),
              alignment: Alignment.center,
              child: Icon(
                TreinoIcon.tabProfile,
                size: 22,
                color: palette.textMuted,
              ),
            ),
            if (hasUnread)
              Positioned(
                top: 0,
                right: 0,
                child: Semantics(
                  label: 'Sin leer',
                  child: Container(
                    key: unreadDotKey,
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: palette.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: palette.bgCard, width: 1.5),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: palette.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w400,
                  fontSize: 12,
                  color: palette.textMuted,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (statusBadge != null) ...[const SizedBox(width: 8), statusBadge!],
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        label,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 10,
          letterSpacing: 0.8,
          color: color,
        ),
      ),
    );
  }
}
