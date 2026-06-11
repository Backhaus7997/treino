import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme/app_palette.dart';
import '../../core/widgets/treino_icon.dart';
import '../chat/application/chat_providers.dart';
import '../payments/application/mi_cuota_provider.dart';
import '../payments/domain/athlete_billing.dart';
import '../profile/application/user_public_profile_providers.dart';
import '../profile/domain/user_public_profile.dart';
import '../reviews/application/review_providers.dart';
import '../reviews/domain/review.dart';
import '../reviews/presentation/widgets/review_bottom_sheet.dart';
import 'application/trainer_discovery_providers.dart' show trainerByIdProvider;
import '../../l10n/app_l10n.dart';
import 'application/trainer_link_providers.dart';
import 'domain/trainer_link.dart';
import 'domain/trainer_link_status.dart';
import 'presentation/trainers_list_screen.dart';

/// Tab Coach del atleta. Combina la discovery (Dev A, Etapa 2) con el
/// estado del vínculo (Etapa 3):
/// - Sin vínculo → renderiza `TrainersListScreen` para que el atleta
///   busque y elija PF. Es el entry natural al flow de Discovery.
/// - status pending → card "esperando confirmación" + botón cancelar.
/// - status active → card con info del PF + botón terminar vínculo.
///
/// Converted to ConsumerStatefulWidget in Fase 6 Etapa 7 to support the
/// 30-day review prompt (Trigger #2). ADR-RV-006.
class AthleteCoachView extends ConsumerStatefulWidget {
  const AthleteCoachView({super.key});

  @override
  ConsumerState<AthleteCoachView> createState() => _AthleteCoachViewState();
}

class _AthleteCoachViewState extends ConsumerState<AthleteCoachView> {
  /// Guards against the post-frame callback firing more than once within the
  /// same widget lifetime. Prevents double-fire on rebuilds. ADR-RV-006.
  bool _promptCheckScheduled = false;

  @override
  void initState() {
    super.initState();
  }

  /// Checks all conditions for showing the 30-day review prompt and shows
  /// the bottom sheet if they are met.
  ///
  /// Conditions (all must be true):
  /// 1. Active link with non-null acceptedAt.
  /// 2. Days since acceptedAt ≥ 30.
  /// 3. No existing review for this link.
  /// 4. SharedPreferences flag `review_prompt_shown_{linkId}` is not set.
  ///
  /// The prefs flag is set BEFORE showing the sheet so that even if the user
  /// cancels without submitting, the prompt is not shown again. ADR-RV-006.
  Future<void> _maybeShow30DayPrompt() async {
    if (_promptCheckScheduled) return;
    _promptCheckScheduled = true;

    if (!mounted) return;

    final link = ref.read(currentAthleteLinkProvider).valueOrNull;
    if (link == null || link.status != TrainerLinkStatus.active) return;

    final acceptedAt = link.acceptedAt;
    if (acceptedAt == null) return;
    if (DateTime.now().toUtc().difference(acceptedAt).inDays < 30) return;

    final reviewKey = '${link.id}:${link.athleteId}';
    // Await the first emission from the stream provider.
    // This is safe because autoDispose keeps the provider alive as long as
    // there is at least one subscriber. ADR-RV-006.
    Review? existingReview;
    try {
      existingReview =
          await ref.read(userReviewForLinkProvider(reviewKey).future);
    } catch (_) {
      // If the stream errors, skip the prompt.
      return;
    }
    if (existingReview != null) return;

    final prefs = await SharedPreferences.getInstance();
    final prefKey = 'review_prompt_shown_${link.id}';
    if (prefs.getBool(prefKey) == true) return;

    // Set flag BEFORE showing the sheet (covers cancel path).
    await prefs.setBool(prefKey, true);

    if (!mounted) return;

    final trainerPub =
        ref.read(userPublicProfileProvider(link.trainerId)).valueOrNull;
    final trainerName = trainerPub?.displayName ??
        'tu Personal Trainer'; // i18n: Fase 6 Etapa 7

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.of(context).bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => ReviewBottomSheet(
        linkId: link.id,
        trainerId: link.trainerId,
        trainerName: trainerName,
        athleteId: link.athleteId,
        triggerVariant: ReviewTriggerVariant.thirtyDay,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final linkAsync = ref.watch(currentAthleteLinkProvider);

    // Trigger #2: fire 30-day prompt after the link provider resolves.
    // Using ref.listen so we react each time the async value transitions to
    // data. The _promptCheckScheduled guard prevents double-fire within the
    // same widget lifetime. ADR-RV-006.
    ref.listen<AsyncValue<TrainerLink?>>(currentAthleteLinkProvider, (_, next) {
      if (next is AsyncData) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _maybeShow30DayPrompt();
        });
      }
    });

    return linkAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
      error: (_, __) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'No pudimos cargar tu vínculo.',
            style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (link) {
        // Sin vínculo → el athlete ve la discovery directamente (entry
        // natural al flow de elegir PF). El botón "PEDIR VÍNCULO" vive
        // dentro de TrainerPublicProfile y al disparar request crea el
        // doc en `trainer_links`; al volver a esta tab, linkAsync emite
        // pending y mostramos la card.
        if (link == null) return const TrainersListScreen();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _LinkStateCard(link: link),
        );
      },
    );
  }
}

// ── Link state card — pending o active ────────────────────────────────────────

class _LinkStateCard extends ConsumerWidget {
  const _LinkStateCard({required this.link});
  final TrainerLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final pubAsync = ref.watch(userPublicProfileProvider(link.trainerId));

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20),
      physics: const ClampingScrollPhysics(),
      children: [
        Container(
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.border, width: 1),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _statusLabel(link.status),
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: link.status == TrainerLinkStatus.active
                      ? palette.accent
                      : palette.textMuted,
                ),
              ),
              const SizedBox(height: 14),
              _TrainerHeader(pubAsync: pubAsync, link: link),
              if (link.status == TrainerLinkStatus.active) ...[
                const SizedBox(height: 14),
                _ShareToggle(link: link),
                const SizedBox(height: 12),
                _AgendaButton(trainerId: link.trainerId),
                const SizedBox(height: 16),
                _CuotaSection(link: link),
              ],
              const SizedBox(height: 18),
              _ActionRow(link: link),
            ],
          ),
        ),
      ],
    );
  }

  String _statusLabel(TrainerLinkStatus s) => switch (s) {
        TrainerLinkStatus.pending => 'SOLICITUD ENVIADA',
        TrainerLinkStatus.active => 'TU PERSONAL TRAINER',
        TrainerLinkStatus.paused => 'VÍNCULO PAUSADO',
        TrainerLinkStatus.terminated => 'VÍNCULO TERMINADO',
      };
}

class _TrainerHeader extends StatelessWidget {
  const _TrainerHeader({required this.pubAsync, required this.link});
  final AsyncValue<UserPublicProfile?> pubAsync;
  final TrainerLink link;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final name = pubAsync.valueOrNull?.displayName ?? '...';
    // Tappable to navigate to the trainer's public profile — pre-existing UX
    // gap (once you have an active link, the discovery flow disappears, so
    // there was no path to the public profile screen). Surfaced during the
    // trainer-reviews smoke when the athlete couldn't reach the review CTA.
    return GestureDetector(
      onTap: () => context.push('/coach/trainer/${link.trainerId}'),
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.bg,
              border: Border.all(color: palette.border, width: 1),
            ),
            alignment: Alignment.center,
            child: Icon(
              TreinoIcon.tabProfile,
              size: 28,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: palette.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  link.status == TrainerLinkStatus.pending
                      ? 'Esperando confirmación'
                      : 'Vinculado desde ${_formatDate(link.acceptedAt ?? link.requestedAt)}',
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}

// ── Share toggle — privacy gate (REQ-COACH-LINK-007..011) ─────────────────────

class _ShareToggle extends ConsumerWidget {
  const _ShareToggle({required this.link});
  final TrainerLink link;

  Future<void> _onChanged(
    BuildContext context,
    WidgetRef ref,
    bool newValue,
  ) async {
    // Enabling sharing → confirmar antes (asymmetric UX: dar acceso es más
    // delicado que revocarlo). Restaurar privacidad es low-stakes y va directo.
    if (newValue == true) {
      final confirmed = await _confirm(
        context,
        '¿Seguro?',
        'Tu PF va a poder ver todas tus sesiones, volumen y racha. '
            'Podés desactivarlo cuando quieras.',
        confirmLabel: 'Compartir',
      );
      if (!confirmed) return;
    }
    // 1. Update the link flag (Firestore rule validates athlete == caller).
    await ref
        .read(trainerLinkRepositoryProvider)
        .setSharedWithTrainer(link.id, newValue);

    // 2. Keep session_shares/{athleteId} in sync with the toggle.
    //    Best-effort: we don't block the UX on this write.
    final shareRepo = ref.read(sessionShareRepositoryProvider);
    if (newValue) {
      unawaited(
        shareRepo.grant(
          athleteId: link.athleteId,
          trainerId: link.trainerId,
        ),
      );
    } else {
      unawaited(shareRepo.revoke(link.athleteId));
    }

    ref.invalidate(currentAthleteLinkProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        'Compartir historial con mi PF',
        style: GoogleFonts.barlow(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: palette.textPrimary,
        ),
      ),
      value: link.sharedWithTrainer,
      activeThumbColor: palette.accent,
      onChanged: (v) => _onChanged(context, ref, v),
    );
  }
}

class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.link});
  final TrainerLink link;

  Future<void> _onCancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      'Cancelar solicitud',
      '¿Seguro que querés cancelar tu solicitud de vínculo? Vas a poder hacer otra después.',
    );
    if (!confirmed) return;
    await ref.read(trainerLinkRepositoryProvider).cancel(link.id);
    ref.invalidate(currentAthleteLinkProvider);
  }

  Future<void> _onTerminate(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      'Terminar vínculo',
      '¿Seguro que querés terminar tu vínculo con este Personal Trainer? Podés volver a pedirle vínculo más adelante.',
    );
    if (!confirmed) return;
    // ignore: use_build_context_synchronously — context is valid here: we
    // checked `confirmed` (dialog closed with user action) and the widget is
    // still mounted because the dialog was still open. The container capture
    // must happen BEFORE the terminate await. ADR-RV-007, ADR-FPS-006.
    if (!context.mounted) return;

    // Capture container + locals BEFORE the async gap (dispose-safe pattern).
    // After terminate(), currentAthleteLinkProvider is invalidated and this
    // widget may be disposed before the await returns. Reading from the
    // container survives disposal. ADR-RV-007, mirrors ADR-FPS-006.
    // ignore: use_build_context_synchronously
    final container = ProviderScope.containerOf(context, listen: false);
    final linkId = link.id;
    final trainerId = link.trainerId;
    final athleteId = link.athleteId;

    // Resolve trainer name from public profile (best-effort, may be null).
    final trainerPub =
        container.read(userPublicProfileProvider(trainerId)).valueOrNull;
    final trainerName = trainerPub?.displayName ??
        'tu Personal Trainer'; // i18n: Fase 6 Etapa 7

    // Resolve existing review before await so we have it for the sheet.
    final reviewKey = '$linkId:$athleteId';
    final existingReview =
        container.read(userReviewForLinkProvider(reviewKey)).valueOrNull;

    await container
        .read(trainerLinkRepositoryProvider)
        .terminate(linkId, reason: 'athlete-terminated');

    container.invalidate(currentAthleteLinkProvider);

    // Show review sheet — context is still valid here because we checked
    // mounted already and the sheet uses the container, not this widget's ref.
    if (context.mounted) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ReviewBottomSheet(
          linkId: linkId,
          trainerId: trainerId,
          trainerName: trainerName,
          athleteId: athleteId,
          existing: existingReview,
          triggerVariant: ReviewTriggerVariant.standard,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    if (link.status == TrainerLinkStatus.pending) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () => _onCancel(context, ref),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: palette.highlight, width: 1),
            foregroundColor: palette.highlight,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9999),
            ),
          ),
          child: Text(
            'CANCELAR SOLICITUD',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.8,
            ),
          ),
        ),
      );
    }
    if (link.status == TrainerLinkStatus.active) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _onMessage(context, ref),
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: palette.bg,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9999),
                ),
              ),
              icon: Icon(TreinoIcon.chat, size: 18, color: palette.bg),
              label: Text(
                'MENSAJE',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _onTerminate(context, ref),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: palette.highlight, width: 1),
                foregroundColor: palette.highlight,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9999),
                ),
              ),
              child: Text(
                'TERMINAR VÍNCULO',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      );
    }
    // Paused — the PF paused the link from Coach Hub. The athlete keeps
    // read-only access to the plan; the only action available is to terminate
    // the relationship (no resume from the athlete side — that's a PF action).
    // Minimum-viable fix for the dead-end the explorer found at the previous
    // SizedBox.shrink() below (REQ-CHLM-013, SCEN-CHLM-018, ADR-CHLM-07).
    if (link.status == TrainerLinkStatus.paused) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () => _onTerminate(context, ref),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: palette.highlight, width: 1),
            foregroundColor: palette.highlight,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9999),
            ),
          ),
          child: Text(
            'TERMINAR VÍNCULO',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.8,
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _onMessage(BuildContext context, WidgetRef ref) async {
    try {
      final chat = await ref.read(chatForLinkProvider(link).future);
      if (!context.mounted) return;
      context.push('/coach/chat/${chat.chatId}?other=${link.trainerId}');
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pudimos abrir el chat. Probá de nuevo.'),
        ),
      );
    }
  }
}

// ── Agenda button — only shown when link is active ────────────────────────────

class _AgendaButton extends StatelessWidget {
  const _AgendaButton({required this.trainerId});
  final String trainerId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final palette = AppPalette.of(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => context.push('/coach/agenda'),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: palette.accent, width: 1),
          foregroundColor: palette.accent,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
          ),
        ),
        icon: Icon(TreinoIcon.tabWorkout, size: 18, color: palette.accent),
        label: Text(
          l10n.agendaButtonLabel,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

// ── Cuota section — what the athlete owes + trainer alias (read-only) ─────────
//
// "Solo informativo" model (decided 2026-06-03): the athlete sees what they
// owe and the alias to transfer to. Money flows offline; the trainer confirms
// receipt from their dashboard ("Cobrado"). No claim/handshake state.

class _CuotaSection extends ConsumerWidget {
  const _CuotaSection({required this.link});
  final TrainerLink link;

  static String _cadenceLabel(BillingCadence c) => switch (c) {
        BillingCadence.mensual => 'Mensual',
        BillingCadence.semanal => 'Semanal',
        BillingCadence.porSesion => 'Por sesión',
        BillingCadence.suelto => 'Suelto',
      };

  static String _formatAmount(int amount) {
    final s = amount.toString();
    final buffer = StringBuffer();
    final offset = s.length % 3;
    if (offset > 0) buffer.write(s.substring(0, offset));
    for (var i = offset; i < s.length; i += 3) {
      if (buffer.isNotEmpty) buffer.write('.');
      buffer.write(s.substring(i, i + 3));
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final cuotaAsync = ref.watch(miCuotaProvider);
    final state = cuotaAsync.valueOrNull;

    // Nothing to show yet (loading) or no active billing context.
    if (state == null) return const SizedBox.shrink();

    final trainerAsync = ref.watch(trainerByIdProvider(link.trainerId));
    final rawAlias = trainerAsync.valueOrNull?.paymentAlias?.trim();
    final alias = (rawAlias == null || rawAlias.isEmpty) ? null : rawAlias;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'TU CUOTA',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1.2,
                    color: palette.textMuted,
                  ),
                ),
              ),
              if (!state.isEmpty)
                Text(
                  '\$${_formatAmount(state.totalArs)}',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: palette.accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (state.isEmpty)
            Row(
              children: [
                Icon(TreinoIcon.check, size: 16, color: palette.accent),
                const SizedBox(width: 8),
                Text(
                  'Estás al día.',
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            )
          else ...[
            for (final item in state.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${item.concept} · ${_cadenceLabel(item.cadence)}',
                        style: GoogleFonts.barlow(
                          fontWeight: FontWeight.w400,
                          fontSize: 13,
                          color: palette.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '\$${_formatAmount(item.amountArs)}',
                      style: GoogleFonts.barlow(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            _AliasRow(alias: alias, palette: palette),
          ],
        ],
      ),
    );
  }
}

class _AliasRow extends StatelessWidget {
  const _AliasRow({required this.alias, required this.palette});
  final String? alias;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    if (alias == null) {
      return Text(
        'Tu PF todavía no cargó un alias de cobro. Coordiná el pago por mensaje.',
        style: GoogleFonts.barlow(
          fontWeight: FontWeight.w400,
          fontSize: 12,
          color: palette.textMuted,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.border, width: 1),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ALIAS PARA TRANSFERIR',
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        letterSpacing: 1.0,
                        color: palette.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      alias!,
                      style: GoogleFonts.barlow(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: palette.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: alias!));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Alias copiado.')),
                    );
                  }
                },
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(TreinoIcon.copy, size: 18, color: palette.accent),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Transferí al alias y avisale a tu PF. Él confirma el pago.',
          style: GoogleFonts.barlow(
            fontWeight: FontWeight.w400,
            fontSize: 12,
            color: palette.textMuted,
          ),
        ),
      ],
    );
  }
}

/// Test-only harness that renders `_LinkStateCard` directly, bypassing the
/// router dependency. Exported for widget tests only.
///
/// @visibleForTesting
class AthleteCoachViewTestHarness extends ConsumerWidget {
  const AthleteCoachViewTestHarness({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linkAsync = ref.watch(currentAthleteLinkProvider);
    return linkAsync.when(
      loading: () => const CircularProgressIndicator(),
      error: (_, __) => const SizedBox.shrink(),
      data: (link) {
        if (link == null) return const SizedBox.shrink();
        return _LinkStateCard(link: link);
      },
    );
  }
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String body, {
  String confirmLabel = 'Confirmar',
}) async {
  final palette = AppPalette.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: palette.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
            backgroundColor: palette.highlight,
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
  return result ?? false;
}
