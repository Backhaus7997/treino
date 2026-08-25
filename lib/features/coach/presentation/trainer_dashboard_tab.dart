import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/analytics/analytics_service.dart';
import '../../../l10n/app_l10n.dart';
import '../../../core/utils/appointment_window.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../coach_hub/presentation/sections/facturacion_planes/plan_limit_paywall.dart';
import '../../coach_hub/presentation/sections/pagos/widgets/thousands_input_formatter.dart';
import '../../payments/application/pagos_por_cobrar_provider.dart';
import '../../payments/application/payment_providers.dart';
import '../../payments/domain/athlete_billing.dart';
import '../../payments/domain/payment.dart';
import '../../profile/application/user_providers.dart';
import '../../profile/application/user_public_profile_providers.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../application/agenda_providers.dart';
import '../application/dashboard_day_counts.dart';
import '../application/follow_up_entry_providers.dart';
import '../application/recent_activity_provider.dart';
import '../application/trained_today_provider.dart';
import '../application/trainer_link_providers.dart';
import '../data/trainer_link_promotion_service.dart';
import '../domain/appointment.dart';
import '../domain/follow_up_entry.dart' show FollowUpTag;
import '../domain/wall_clock.dart';

// Re-export so the mobile test (trainer_dashboard_day_counts_test.dart) that
// imports dashboardDayCounts/DashboardDayCounts from this file keeps compiling
// without modification.
export '../application/dashboard_day_counts.dart'
    show dashboardDayCounts, DashboardDayCounts;
import 'widgets/appointment_detail_sheet.dart';
import '../domain/trainer_link.dart';
import '../domain/trainer_link_status.dart';

/// Trainer "Hoy" / Dashboard sub-tab — matches docs/app-trainer/screens/dashboard.
///
/// Sections wired to real data:
///   - Header (greeting + date + avatar)
///   - Resumen del día (counts derived from today's appointments)
///   - Próximas sesiones (next 3 confirmed appointments from now)
///   - CTAs: Asignar rutina, Invitar alumno (stub for now)
///
/// Sections shown visually with placeholder until backing data exists:
///   - Entrenaron hoy (needs sessions provider scoped to trainer's athletes)
///   - Actividad reciente (same)
///   - Pagos por cobrar (no payments module yet)
class TrainerDashboardTab extends ConsumerWidget {
  const TrainerDashboardTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);

    return ListView(
      // Explicit padding overrides the ambient MediaQuery inset, so the
      // floating bar's height must be added back — otherwise the last row
      // (CTA buttons) can never scroll out from behind the translucent bar.
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const _DashboardHeader(),
        const SizedBox(height: 18),
        // #393: pending requests are NOT shown inline here anymore — they live
        // in the bell modal (_showPendingRequestsSheet) so they don't clutter
        // the dashboard.
        const _ResumenDelDiaCard(),
        const SizedBox(height: 20),
        _SectionHeader(
          label: AppL10n.of(context).dashboardProximasSesionesSectionLabel,
          trailingLabel: AppL10n.of(context).dashboardAgendaTrailingLabel,
          trailingOnTap: () => context.go('/coach?tab=agenda'),
        ),
        const SizedBox(height: 8),
        const _ProximasSesionesList(),
        const SizedBox(height: 20),
        _SectionHeader(
          label: AppL10n.of(context).dashboardEntrenaronHoySectionLabel,
          trailingLabel: AppL10n.of(context).dashboardDejarFeedbackLabel,
          trailingOnTap: () => _showDejarFeedbackSheet(context),
        ),
        const SizedBox(height: 8),
        const _EntrenaronHoyList(),
        const SizedBox(height: 20),
        _SectionHeader(
          label: AppL10n.of(context).dashboardActividadRecienteSectionLabel,
        ),
        const SizedBox(height: 8),
        const _ActividadRecienteList(),
        const SizedBox(height: 20),
        _PagosPorCobrarSection(palette: palette),
        const SizedBox(height: 20),
        const _BottomActions(),
      ],
    );
  }
}

// ── Header (greeting + date + bell + avatar) ─────────────────────────────────

class _DashboardHeader extends ConsumerWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final profileAsync = ref.watch(userProfileProvider);
    final linksAsync = ref.watch(trainerLinksStreamProvider);

    final name = profileAsync.valueOrNull?.displayName ?? '';
    final firstName = name.isEmpty ? '' : name.split(RegExp(r'\s+')).first;
    final initials = _initials(name);
    final pendingCount = (linksAsync.valueOrNull ?? const [])
        .where((l) => l.status == TrainerLinkStatus.pending)
        .length;
    // A failed links read must not silently hide the badge: flag it so the bell
    // shows an error dot (and its sheet a retry) instead of a false empty "0".
    final linksHasError = linksAsync.hasError && !linksAsync.hasValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _formatHeaderDate(AppL10n.of(context), DateTime.now()),
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 1.2,
            color: palette.accent,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                firstName.isEmpty
                    ? AppL10n.of(context).dashboardHolaSinNombre
                    : AppL10n.of(
                        context,
                      ).dashboardHolaConNombre(firstName.toUpperCase()),
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 28,
                  letterSpacing: 0.5,
                  color: palette.textPrimary,
                ),
              ),
            ),
            _BellWithBadge(
              badgeCount: pendingCount,
              showError: linksHasError,
              palette: palette,
              onTap: () => _showPendingRequestsSheet(context),
            ),
            const SizedBox(width: 12),
            // Shortcut straight to the professional-profile EDITOR, not to the
            // PERFIL tab: from the dashboard the useful destination is the
            // form, not the tab root the trainer would then have to tap
            // through.
            //
            // `push`, not `go`: ProfileEditTrainerScreen ends its edit-mode
            // save with `context.pop()` (ADR-TPO-006). Navigating with `go`
            // would leave nothing to pop and strand the trainer on the form
            // after saving.
            //
            // No `?mode=onboarding` — that param is for the first-run gate;
            // any other value defaults to edit mode, which is what we want.
            //
            // Wrapped HERE and not inside _AvatarInitials: that widget is also
            // used for athlete rows in ENTRENARON HOY and in the feedback
            // picker, where it must stay inert.
            Semantics(
              button: true,
              // `container: true` is what makes this its OWN semantics node.
              // Without it the annotation merges into the enclosing node and
              // the whole header — date, greeting, bell label and this one —
              // is announced as a single blob.
              container: true,
              label: AppL10n.of(context).a11yDashboardAvatarButton,
              child: GestureDetector(
                onTap: () => context.push('/profile/edit-trainer'),
                behavior: HitTestBehavior.opaque,
                // The avatar itself is 36px — under the 44pt minimum touch
                // target. `opaque` makes the whole padded box tappable.
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  child: Center(
                    // The initials render as a Text that would otherwise merge
                    // into the label and be read out as "Editar tu perfil
                    // profesional MP". They are decorative — derived from the
                    // display name the trainer already knows is theirs.
                    //
                    // Excluded HERE, wrapping only the decorative subtree, and
                    // NOT via `excludeSemantics: true` on the Semantics above:
                    // that flag drops the semantics of EVERY descendant,
                    // including the tap action the GestureDetector contributes.
                    // The node was still announced as a button but VoiceOver's
                    // double-tap had no action to fire. Same shape as
                    // _BellWithBadge.
                    child: ExcludeSemantics(
                      child: _AvatarInitials(
                        initials: initials.isEmpty ? '·' : initials,
                        palette: palette,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BellWithBadge extends StatelessWidget {
  const _BellWithBadge({
    required this.badgeCount,
    required this.palette,
    required this.onTap,
    this.showError = false,
  });
  final int badgeCount;
  final AppPalette palette;

  /// Fires when tapped. Only wired when [badgeCount] > 0 — a zero badge has no
  /// pending requests to show, so the bell stays inert (#393).
  final VoidCallback onTap;

  /// The links stream failed: show an amber dot (not a count) so the trainer
  /// knows to tap, instead of a badge silently hidden as if there were none.
  final bool showError;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    // #393: the bell was a bare Icon with no tap handler. It opens a modal
    // sheet listing the pending link requests (accept/decline).
    //
    // It used to be gated on `badgeCount > 0` and sat INERT at zero, which
    // read as broken — a trainer with no requests tapped it and nothing
    // happened, with no way to tell that from a bug. It is always tappable
    // now; the sheet owns the empty state.
    return Semantics(
      label: showError
          ? l10n.agendaGenericError
          : l10n.homePendingRequestsA11y(badgeCount),
      button: true,
      // Without `container: true` this annotation merged into the enclosing
      // header node, so the pending count was announced glued to the date and
      // the greeting ("MARTES 28 JULIO HOLA, MATEO 0 solicitudes pendientes")
      // instead of as its own control.
      container: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(TreinoIcon.bell, size: 22, color: palette.textPrimary),
              if (showError)
                // Amber dot: the count is unknown (read failed), so show an
                // attention marker that invites a tap rather than a false count.
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: palette.warning,
                      shape: BoxShape.circle,
                      border: Border.all(color: palette.bg, width: 1),
                    ),
                  ),
                )
              else if (badgeCount > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: palette.accent,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      border: Border.all(color: palette.bg, width: 1),
                    ),
                    child: Text(
                      badgeCount > 9 ? '9+' : '$badgeCount',
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        color: TreinoButtonTokens.foreground(context),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Test-only harness that renders `_BellWithBadge` directly, so the #393
/// tap/inert behaviour is unit-testable without the full dashboard's provider
/// graph (mirrors [AddSueltoSheetTestHarness]).
///
/// @visibleForTesting
class BellWithBadgeTestHarness extends StatelessWidget {
  const BellWithBadgeTestHarness({
    super.key,
    required this.badgeCount,
    required this.onTap,
    this.showError = false,
  });

  final int badgeCount;
  final VoidCallback onTap;
  final bool showError;

  @override
  Widget build(BuildContext context) => _BellWithBadge(
        badgeCount: badgeCount,
        showError: showError,
        palette: AppPalette.of(context),
        onTap: onTap,
      );
}

class _AvatarInitials extends StatelessWidget {
  const _AvatarInitials({required this.initials, required this.palette});
  final String initials;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: palette.bgCard,
        border: Border.all(color: palette.accent, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          letterSpacing: 0.5,
          color: palette.accent,
        ),
      ),
    );
  }
}

// ── Pending request card (used by the bell modal, #393) ───────────────────────

class _PendingRequestCard extends ConsumerStatefulWidget {
  const _PendingRequestCard({required this.link});
  final TrainerLink link;

  @override
  ConsumerState<_PendingRequestCard> createState() =>
      _PendingRequestCardState();
}

class _PendingRequestCardState extends ConsumerState<_PendingRequestCard> {
  // Guards against double-submit: a fast double-tap before the stream rebuilds
  // and removes this card would otherwise fire accept/decline (and analytics)
  // twice. Stays true on success — the card is about to disappear; only resets
  // on error so the trainer can retry.
  bool _busy = false;

  // El catch resetea _busy Y muestra feedback (hallazgo H5): antes solo
  // reseteaba el flag, así que un fallo (permission-denied, rules) dejaba al PF
  // creyendo que aceptó/rechazó cuando no pasó nada. `_showError` chequea
  // mounted porque corre después del await.
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(trainerLinkRepositoryProvider).decline(widget.link.id);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      _showError('No pudimos rechazar la solicitud. Probá de nuevo.');
    }
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppL10n.of(context);
    try {
      await ref
          .read(trainerLinkPromotionServiceProvider)
          .accept(widget.link.id);
      ref
          .read(analyticsServiceProvider)
          .logLinkAccepted(linkId: widget.link.id);
    } on LinkPromotionFailure$PlanLimitReached catch (failure) {
      if (!mounted) return;
      setState(() => _busy = false);
      unawaited(
        showPlanLimitPaywall(
          context,
          currentTier: failure.tier,
          reason: failure.reason == 'subscription-inactive'
              ? PlanLimitReason.subscriptionInactive
              : PlanLimitReason.planLimit,
        ),
      );
    } on LinkPromotionFailure$PromotionPrecondition {
      if (mounted) setState(() => _busy = false);
      _showError(l10n.coachHubDashboardAcceptPrecondition);
    } on LinkPromotionFailure catch (_) {
      if (mounted) setState(() => _busy = false);
      _showError(l10n.coachHubDashboardAcceptUnavailable);
    } catch (_) {
      // QA H5: el catch-all NO se puede angostar a LinkPromotionFailure. Lo
      // que no sea de esa jerarquia (un bug del servicio, un error de
      // plataforma) escaparia dejando _busy en true para siempre: boton
      // muerto, sin feedback, y el PF creyendo que acepto cuando no paso
      // nada. Es exactamente el bug que este metodo ya tuvo una vez.
      if (mounted) setState(() => _busy = false);
      _showError(l10n.coachHubDashboardAcceptUnavailable);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final profileAsync = ref.watch(
      userPublicProfileProvider(widget.link.athleteId),
    );
    final name =
        profileAsync.valueOrNull?.displayName ?? l10n.dashboardAlumnoFallback;
    final initials = _initials(name);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _AvatarInitials(initials: initials, palette: palette),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: palette.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _decline,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: palette.highlight, width: 1),
                    foregroundColor: palette.highlight,
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
                  child: Text(
                    l10n.dashboardRechazarLabel,
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _busy ? null : _accept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: TreinoButtonTokens.foreground(context),
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
                  child: Text(
                    l10n.dashboardAceptarLabel,
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
        ],
      ),
    );
  }
}

// ── Pending-requests modal (opened from the header bell, #393) ────────────────

/// #393: the header bell opens this sheet listing the trainer's pending link
/// requests (accept/decline). There is no separate requests screen and no
/// in-app notification centre (only push FCM), so this modal is the single
/// place the trainer reviews them. (The requests used to also render inline in
/// the dashboard, but that duplicated the modal and cluttered the home.)
/// Opens the "Dejar feedback" sheet from the ENTRENARON HOY section header.
///
/// The link had NO handler until now: `_SectionHeader` renders a trailing
/// label with `trailingOnTap == null` in `textMuted`, so it sat there looking
/// deliberately inert. The mockup (docs/app-trainer/screens/dashboard) shows
/// it in accent — an active link — but never designed a destination screen,
/// so the surface below is new. It writes a [FollowUpEntry] tagged
/// `entrenamiento`, the same private trainer→athlete note the Coach Hub (web)
/// already creates; only the mobile UI was missing.
void _showDejarFeedbackSheet(BuildContext context) {
  final palette = AppPalette.of(context);
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: palette.bgCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (_) => const _DejarFeedbackSheet(),
  );
}

/// Two-step sheet: pick an athlete who trained today, then write the note.
///
/// Athletes come from [trainedTodayProvider] — the SAME source the section
/// lists — so the sheet can never offer someone the trainer isn't looking at.
class _DejarFeedbackSheet extends ConsumerStatefulWidget {
  const _DejarFeedbackSheet();

  @override
  ConsumerState<_DejarFeedbackSheet> createState() =>
      _DejarFeedbackSheetState();
}

class _DejarFeedbackSheetState extends ConsumerState<_DejarFeedbackSheet> {
  final _controller = TextEditingController();
  String? _athleteId;
  String? _athleteName;
  bool _saving = false;
  bool _failed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final trainerId = ref.read(currentUidProvider) ?? '';
    final text = _controller.text.trim();
    if (trainerId.isEmpty || _athleteId == null || text.isEmpty) return;

    setState(() {
      _saving = true;
      _failed = false;
    });

    try {
      await ref.read(followUpEntryRepositoryProvider).add(
            trainerId: trainerId,
            athleteId: _athleteId!,
            text: text,
            tag: FollowUpTag.entrenamiento,
          );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _failed = true;
      });
      return;
    }

    if (!mounted) return;
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.dashboardFeedbackSaved)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return SafeArea(
      child: Padding(
        // viewInsets so the composer stays above the keyboard.
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_athleteId != null)
                  GestureDetector(
                    onTap: () => setState(() {
                      _athleteId = null;
                      _athleteName = null;
                      _failed = false;
                    }),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Icon(
                        TreinoIcon.back,
                        size: 20,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    _athleteName ?? l10n.dashboardFeedbackSheetTitle,
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      letterSpacing: 1.0,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_athleteId == null)
              _FeedbackAthletePicker(
                onPick: (id, name) => setState(() {
                  _athleteId = id;
                  _athleteName = name;
                }),
              )
            else ...[
              TextField(
                controller: _controller,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                enabled: !_saving,
                onChanged: (_) => setState(() {}),
                style: GoogleFonts.barlow(
                  fontSize: 14,
                  color: palette.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: l10n.dashboardFeedbackComposerHint,
                  hintStyle: GoogleFonts.barlow(
                    fontSize: 14,
                    color: palette.textMuted,
                  ),
                  filled: true,
                  fillColor: palette.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.border),
                  ),
                ),
              ),
              if (_failed) ...[
                const SizedBox(height: 10),
                Text(
                  l10n.dashboardFeedbackSaveError,
                  style: GoogleFonts.barlow(
                    fontSize: 13,
                    color: palette.danger,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  // Disabled on empty text — an empty FollowUpEntry is noise
                  // in the athlete's history, not a saved note.
                  onPressed:
                      _saving || _controller.text.trim().isEmpty ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: TreinoButtonTokens.foreground(context),
                    minimumSize: const Size.fromHeight(48),
                    shape: const StadiumBorder(),
                  ),
                  child: _saving
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: TreinoButtonTokens.foreground(context),
                          ),
                        )
                      : Text(
                          l10n.dashboardFeedbackSave,
                          style: GoogleFonts.barlowCondensed(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            letterSpacing: 0.8,
                          ),
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Step 1 — the athletes who trained today, reusing [trainedTodayProvider].
class _FeedbackAthletePicker extends ConsumerWidget {
  const _FeedbackAthletePicker({required this.onPick});

  final void Function(String athleteId, String displayName) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final todayAsync = ref.watch(trainedTodayProvider);

    if (todayAsync.isLoading && !todayAsync.hasValue) {
      return _PlaceholderCard(
        palette: palette,
        message: l10n.dashboardCargando,
      );
    }
    if (todayAsync.hasError && !todayAsync.hasValue) {
      return _PlaceholderCard(
        palette: palette,
        message: l10n.dashboardErrorActividad,
      );
    }

    final entries = todayAsync.valueOrNull ?? const <TrainedTodayEntry>[];
    if (entries.isEmpty) {
      return _PlaceholderCard(
        palette: palette,
        message: l10n.dashboardNadieEntreno,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.dashboardFeedbackPickAthlete,
          style: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
        ),
        const SizedBox(height: 10),
        // Bounded so a trainer with many athletes still gets a sheet that
        // fits — the list scrolls instead of pushing the header off-screen.
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) =>
                _FeedbackAthleteTile(entry: entries[i], onPick: onPick),
          ),
        ),
      ],
    );
  }
}

class _FeedbackAthleteTile extends ConsumerWidget {
  const _FeedbackAthleteTile({required this.entry, required this.onPick});

  final TrainedTodayEntry entry;
  final void Function(String athleteId, String displayName) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    // Same name-resolution contract as _EntrenaronHoyRow: a raw uid is not a
    // name, so it falls back to the generic label.
    final profileAsync = ref.watch(userPublicProfileProvider(entry.athleteId));
    final rawName = profileAsync.valueOrNull?.displayName ?? '';
    final showName = rawName.isEmpty || _looksLikeUid(rawName)
        ? AppL10n.of(context).dashboardAlumnoFallback
        : rawName;

    return InkWell(
      onTap: () => onPick(entry.athleteId, showName),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: palette.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            _AvatarInitials(initials: _initials(showName), palette: palette),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                showName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.barlow(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
            ),
            Icon(TreinoIcon.forward, size: 14, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Test-only harness that renders the "Dejar feedback" sheet content directly,
/// so the picker → composer → save flow is testable without driving the
/// bottom-sheet plumbing (mirrors [PendingRequestsSheetTestHarness]).
///
/// @visibleForTesting
class DejarFeedbackSheetTestHarness extends StatelessWidget {
  const DejarFeedbackSheetTestHarness({super.key});

  @override
  Widget build(BuildContext context) => const _DejarFeedbackSheet();
}

void _showPendingRequestsSheet(BuildContext context) {
  final palette = AppPalette.of(context);
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: palette.bgCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (_) => const _PendingRequestsSheet(),
  );
}

class _PendingRequestsSheet extends ConsumerStatefulWidget {
  const _PendingRequestsSheet();

  @override
  ConsumerState<_PendingRequestsSheet> createState() =>
      _PendingRequestsSheetState();
}

class _PendingRequestsSheetState extends ConsumerState<_PendingRequestsSheet> {
  /// Latches once the sheet has shown at least one request.
  ///
  /// It distinguishes the two ways of ending up with an empty list, which need
  /// OPPOSITE behaviour:
  /// - opened with none → show the empty state and STAY (the bell is now
  ///   always tappable, so this is a legitimate way to open the sheet);
  /// - opened with some and the last one was just accepted/declined →
  ///   auto-close, so the sheet does not sit there with nothing in it.
  ///
  /// Written during build without setState on purpose: it never needs to
  /// trigger a rebuild of its own — the stream already rebuilds us, and this
  /// only records what that rebuild showed.
  bool _hadAny = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final linksAsync = ref.watch(trainerLinksStreamProvider);

    // A failed read must not read as "no requests": show a retry, not the empty
    // state (nor a "(0)" title) that would hide a pending request behind a lie.
    // Early return keeps it clear of the had-some-then-none auto-close below.
    if (linksAsync.hasError && !linksAsync.hasValue) {
      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.agendaGenericError,
              style: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => ref.invalidate(trainerLinksStreamProvider),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                l10n.coachRetryLabel,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.8,
                  color: palette.accent,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final pending = (linksAsync.valueOrNull ?? const <TrainerLink>[])
        .where((l) => l.status == TrainerLinkStatus.pending)
        .toList();

    if (pending.isNotEmpty) _hadAny = true;

    if (pending.isEmpty && _hadAny) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
    }

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.dashboardSolicitudesPendientesTitle(pending.length),
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                letterSpacing: 1.2,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            if (pending.isEmpty)
              Text(
                l10n.dashboardSolicitudesPendientesEmpty,
                style: GoogleFonts.barlow(
                  fontSize: 13,
                  color: palette.textMuted,
                ),
              ),
            for (final link in pending) ...[
              _PendingRequestCard(link: link),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

/// Test-only harness that renders the #393 pending-requests modal content
/// directly, so its list behaviour is testable without driving the bell +
/// bottom-sheet plumbing (mirrors [AddSueltoSheetTestHarness]).
///
/// @visibleForTesting
class PendingRequestsSheetTestHarness extends StatelessWidget {
  const PendingRequestsSheetTestHarness({super.key});

  @override
  Widget build(BuildContext context) => const _PendingRequestsSheet();
}

// ── Resumen del día (3 stat columns) ──────────────────────────────────────────

class _ResumenDelDiaCard extends ConsumerWidget {
  const _ResumenDelDiaCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final trainerId = ref.watch(currentUidProvider) ?? '';
    final apptAsync = trainerId.isEmpty
        ? const AsyncValue<List<Appointment>>.data(<Appointment>[])
        : ref.watch(
            trainerAppointmentsStreamProvider(_appointmentsKey(trainerId)),
          );

    // Distinguir loading/error de un día genuinamente en cero (QA H3): antes
    // `apptAsync.valueOrNull ?? []` colapsaba AMBOS a 0/0/0, así que un
    // permission-denied (p.ej. App Check no registrado) se leía como
    // "0 pendientes, 0 hechas, 0 canceladas" — un día tranquilo, no un fallo.
    // El hermano _ProximasSesionesList ya distinguía los estados con el mismo
    // provider; esto lo empareja. Loading muestra "—"; error, un mensaje.
    final Widget body = apptAsync.when(
      loading: () =>
          _statsRow(context, palette, pending: '—', done: '—', cancelled: '—'),
      error: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          l10n.dashboardErrorResumen,
          style: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
        ),
      ),
      data: (all) {
        // QA-HOME-001: startsAt is Argentina wall-clock, so "now" must be too.
        final counts = dashboardDayCounts(all, argentinaNow());
        return _statsRow(
          context,
          palette,
          pending: '${counts.pending}',
          done: '${counts.done}',
          cancelled: '${counts.cancelled}',
        );
      },
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.dashboardResumenDelDiaTitle,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }

  Widget _statsRow(
    BuildContext context,
    AppPalette palette, {
    required String pending,
    required String done,
    required String cancelled,
  }) {
    final l10n = AppL10n.of(context);
    return Row(
      children: [
        _StatColumn(
          value: pending,
          label: l10n.dashboardStatPendientes,
          color: palette.accent,
          palette: palette,
        ),
        _Divider(palette: palette),
        _StatColumn(
          value: done,
          label: l10n.dashboardStatCompletadas,
          color: palette.textPrimary,
          palette: palette,
        ),
        _Divider(palette: palette),
        _StatColumn(
          value: cancelled,
          label: l10n.dashboardStatCanceladas,
          color: palette.danger,
          palette: palette,
        ),
      ],
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({
    required this.value,
    required this.label,
    required this.color,
    required this.palette,
  });

  final String value;
  final String label;
  final Color color;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 28,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 10,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: palette.border,
    );
  }
}

// ── Section header with optional trailing link ────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    this.trailingLabel,
    this.trailingOnTap,
  });

  final String label;
  final String? trailingLabel;
  final VoidCallback? trailingOnTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
        ),
        if (trailingLabel != null)
          GestureDetector(
            onTap: trailingOnTap,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Text(
                  trailingLabel!,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: trailingOnTap == null
                        ? palette.textMuted
                        : palette.accent,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  TreinoIcon.forward,
                  size: 14,
                  color: trailingOnTap == null
                      ? palette.textMuted
                      : palette.accent,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Próximas sesiones list ────────────────────────────────────────────────────

class _ProximasSesionesList extends ConsumerWidget {
  const _ProximasSesionesList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final trainerId = ref.watch(currentUidProvider) ?? '';
    if (trainerId.isEmpty) {
      return _PlaceholderCard(
        palette: palette,
        message: l10n.dashboardIniciaSesion,
      );
    }
    final apptAsync = ref.watch(
      trainerAppointmentsStreamProvider(_appointmentsKey(trainerId)),
    );

    return apptAsync.when(
      loading: () =>
          _PlaceholderCard(palette: palette, message: l10n.dashboardCargando),
      error: (_, __) => _PlaceholderCard(
        palette: palette,
        message: l10n.dashboardErrorTurnos,
      ),
      data: (all) {
        // QA-HOME-001: startsAt is Argentina wall-clock; compare against ART
        // wall-clock "now" so the next few hours aren't dropped.
        final now = argentinaNow();
        final upcoming = all
            .where(
              (a) =>
                  a.status == AppointmentStatus.confirmed &&
                  a.startsAt.isAfter(now),
            )
            .toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
        final next3 = upcoming.take(3).toList();

        if (next3.isEmpty) {
          return _PlaceholderCard(
            palette: palette,
            message: l10n.dashboardSinTurnosProximos,
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: palette.border, width: 1),
          ),
          child: Column(
            children: [
              for (int i = 0; i < next3.length; i++) ...[
                if (i > 0)
                  Divider(
                    color: palette.border,
                    height: 1,
                    thickness: 1,
                    indent: 14,
                    endIndent: 14,
                  ),
                _ProximaSesionRow(appointment: next3[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ProximaSesionRow extends ConsumerWidget {
  const _ProximaSesionRow({required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final profileAsync = ref.watch(
      userPublicProfileProvider(appointment.athleteId),
    );
    final athleteName =
        profileAsync.valueOrNull?.displayName ?? appointment.athleteDisplayName;
    final showName = _looksLikeUid(athleteName)
        ? AppL10n.of(context).dashboardAlumnoFallback
        : athleteName;
    final initials = _initials(showName);

    return InkWell(
      onTap: () => showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        backgroundColor: AppPalette.of(context).bgCard,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
        builder: (_) => AppointmentDetailSheet(
          appointment: appointment,
          trainerId: ref.watch(currentUidProvider) ?? '',
        ),
      ),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                _formatTime(appointment.startsAt),
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: palette.accent,
                ),
              ),
            ),
            _AvatarInitials(initials: initials, palette: palette),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    showName,
                    style: GoogleFonts.barlow(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: palette.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_formatDateLabel(AppL10n.of(context), appointment.startsAt)} · ${appointment.durationMin} min',
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
            const SizedBox(width: 8),
            Icon(TreinoIcon.forward, size: 18, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}

// ── Entrenaron hoy list ───────────────────────────────────────────────────────

class _EntrenaronHoyList extends ConsumerWidget {
  const _EntrenaronHoyList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final todayAsync = ref.watch(trainedTodayProvider);

    if (todayAsync.isLoading && !todayAsync.hasValue) {
      return _PlaceholderCard(
        palette: palette,
        message: l10n.dashboardCargando,
      );
    }
    if (todayAsync.hasError && !todayAsync.hasValue) {
      return _PlaceholderCard(
        palette: palette,
        message: l10n.dashboardErrorActividad,
      );
    }

    final entries = todayAsync.valueOrNull ?? const [];
    if (entries.isEmpty) {
      return _PlaceholderCard(
        palette: palette,
        message: l10n.dashboardNadieEntreno,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Column(
        children: [
          for (int i = 0; i < entries.length; i++) ...[
            if (i > 0)
              Divider(
                color: palette.border,
                height: 1,
                thickness: 1,
                indent: 14,
                endIndent: 14,
              ),
            _EntrenaronHoyRow(entry: entries[i]),
          ],
        ],
      ),
    );
  }
}

class _EntrenaronHoyRow extends ConsumerWidget {
  const _EntrenaronHoyRow({required this.entry});
  final TrainedTodayEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final profileAsync = ref.watch(userPublicProfileProvider(entry.athleteId));
    final rawName = profileAsync.valueOrNull?.displayName ?? '';
    final showName = rawName.isEmpty || _looksLikeUid(rawName)
        ? AppL10n.of(context).dashboardAlumnoFallback
        : rawName;
    final initials = _initials(showName);
    final session = entry.session;

    return InkWell(
      onTap: () => context.push('/coach/athlete/${entry.athleteId}'),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            _AvatarInitials(initials: initials, palette: palette),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    showName,
                    style: GoogleFonts.barlow(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: palette.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // finishedAt is a real UTC instant — localize before
                    // formatting (#380). NOTE: _formatTime is shared with
                    // appointment.startsAt (ADR-7 wall-clock, line ~690) which
                    // must stay raw — so convert HERE at the call site, never
                    // inside _formatTime.
                    '${session.routineName} · ${_formatTime(session.finishedAt!.toLocal())}',
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
            const SizedBox(width: 8),
            Text(
              '${session.totalVolumeKg.toStringAsFixed(0)} kg',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Actividad reciente ────────────────────────────────────────────────────────

class _ActividadRecienteList extends ConsumerWidget {
  const _ActividadRecienteList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final activityAsync = ref.watch(recentActivityProvider);

    if (activityAsync.isLoading && !activityAsync.hasValue) {
      return _PlaceholderCard(
        palette: palette,
        message: l10n.dashboardCargando,
      );
    }
    if (activityAsync.hasError && !activityAsync.hasValue) {
      return _PlaceholderCard(
        palette: palette,
        message: l10n.dashboardErrorActividad,
      );
    }

    final entries = activityAsync.valueOrNull ?? const [];
    if (entries.isEmpty) {
      return _PlaceholderCard(
        palette: palette,
        message: l10n.dashboardSinActividadReciente,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Column(
        children: [
          for (int i = 0; i < entries.length; i++) ...[
            if (i > 0)
              Divider(
                color: palette.border,
                height: 1,
                thickness: 1,
                indent: 14,
                endIndent: 14,
              ),
            _ActividadRecienteRow(entry: entries[i]),
          ],
        ],
      ),
    );
  }
}

class _ActividadRecienteRow extends ConsumerWidget {
  const _ActividadRecienteRow({required this.entry});
  final RecentActivityEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final profileAsync = ref.watch(userPublicProfileProvider(entry.athleteId));
    final rawName = profileAsync.valueOrNull?.displayName ?? '';
    final showName = rawName.isEmpty || _looksLikeUid(rawName)
        ? AppL10n.of(context).dashboardAlumnoFallback
        : rawName;
    final initials = _initials(showName);
    final session = entry.session;

    return InkWell(
      onTap: () => context.push('/coach/athlete/${entry.athleteId}'),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            _AvatarInitials(initials: initials, palette: palette),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    showName,
                    style: GoogleFonts.barlow(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: palette.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // Date (not time-of-day) — differentiates this rolling feed
                    // from the "Entrenaron hoy" today snapshot above.
                    '${session.routineName} · ${_formatArtDate(session.finishedAt!)}',
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
            const SizedBox(width: 8),
            Text(
              '${session.totalVolumeKg.toStringAsFixed(0)} kg',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Formats a UTC instant as its ART calendar date, `d/M` (e.g. "15/7").
String _formatArtDate(DateTime finishedAt) {
  final art = toArgentina(finishedAt.toUtc());
  return '${art.day}/${art.month}';
}

// ── Pagos por cobrar section ──────────────────────────────────────────────────

class _PagosPorCobrarSection extends ConsumerWidget {
  const _PagosPorCobrarSection({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainerId = ref.watch(currentUidProvider);

    void openAddSueltoSheet() {
      if (trainerId == null) return;
      showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        backgroundColor: palette.bgCard,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
        builder: (_) => _AddSueltoSheet(trainerId: trainerId),
      );
    }

    final l10n = AppL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          label: l10n.dashboardPagosPorCobrarTitle,
          trailingLabel: l10n.dashboardCobroTrailingLabel,
          trailingOnTap: openAddSueltoSheet,
        ),
        const SizedBox(height: 8),
        const _PagosPorCobrarList(),
      ],
    );
  }
}

class _PagosPorCobrarList extends ConsumerWidget {
  const _PagosPorCobrarList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final cobrosAsync = ref.watch(pagosPorCobrarProvider);

    if (cobrosAsync.isLoading && !cobrosAsync.hasValue) {
      return _PlaceholderCard(
        palette: palette,
        message: l10n.dashboardCargando,
      );
    }
    if (cobrosAsync.hasError && !cobrosAsync.hasValue) {
      return _PlaceholderCard(
        palette: palette,
        message: l10n.dashboardErrorCobros,
      );
    }

    final cobros = cobrosAsync.valueOrNull ?? const [];
    if (cobros.isEmpty) {
      return _PlaceholderCard(
        palette: palette,
        message: l10n.dashboardSinCobros,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Column(
        children: [
          for (int i = 0; i < cobros.length; i++) ...[
            if (i > 0)
              Divider(
                color: palette.border,
                height: 1,
                thickness: 1,
                indent: 14,
                endIndent: 14,
              ),
            _CobroPendienteRow(cobro: cobros[i]),
          ],
        ],
      ),
    );
  }
}

class _CobroPendienteRow extends ConsumerWidget {
  const _CobroPendienteRow({required this.cobro});
  final CobroPendiente cobro;

  static String _cadenceLabel(AppL10n l10n, BillingCadence c) => switch (c) {
        BillingCadence.mensual => l10n.dashboardCadenceMensual,
        BillingCadence.semanal => l10n.dashboardCadenceSemanal,
        BillingCadence.porSesion => l10n.dashboardCadencePorSesion,
        BillingCadence.suelto => l10n.dashboardCadenceSuelto,
      };

  static String _formatAmount(int amount) {
    // Thousands separator for ARS amounts
    final s = amount.toString();
    final buffer = StringBuffer();
    int offset = s.length % 3;
    if (offset > 0) buffer.write(s.substring(0, offset));
    for (int i = offset; i < s.length; i += 3) {
      if (buffer.isNotEmpty) buffer.write('.');
      buffer.write(s.substring(i, i + 3));
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final profileAsync = ref.watch(userPublicProfileProvider(cobro.athleteId));
    final rawName = profileAsync.valueOrNull?.displayName ?? '';
    final showName = rawName.isEmpty || _looksLikeUid(rawName)
        ? l10n.dashboardAlumnoFallback
        : rawName;
    final initials = _initials(showName);
    final trainerId = ref.watch(currentUidProvider) ?? '';

    Future<void> onCobrado() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: palette.bgCard,
          title: Text(
            l10n.dashboardMarcarCobradoTitle,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: palette.textPrimary,
            ),
          ),
          content: Text(
            '${cobro.concept} — \$${_formatAmount(cobro.amountArs)}',
            style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                l10n.dashboardCancelarLabel,
                style: TextStyle(color: palette.textMuted),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                l10n.dashboardCobradoLabel,
                style: TextStyle(color: palette.accent),
              ),
            ),
          ],
        ),
      );

      if (confirmed != true || !context.mounted) return;

      final repo = ref.read(paymentRepositoryProvider);
      final now = DateTime.now().toUtc();

      try {
        switch (cobro.cadence) {
          case BillingCadence.mensual:
          case BillingCadence.semanal:
            // Derive periodKey in ART: the bucket identity is a calendar
            // concept and MUST match the CF (createdAt/paidAt below stay UTC).
            final now2 = argentinaNow();
            final periodKey = cobro.cadence == BillingCadence.mensual
                ? '${now2.year}-${now2.month.toString().padLeft(2, '0')}'
                : isoWeekPeriodKey(now2);
            await repo.add(
              Payment(
                id: '',
                trainerId: trainerId,
                athleteId: cobro.athleteId,
                amountArs: cobro.amountArs,
                concept: cobro.concept,
                status: PaymentStatus.paid,
                periodKey: periodKey,
                createdAt: now,
                paidAt: now,
              ),
            );

          case BillingCadence.porSesion:
            await repo.add(
              Payment(
                id: '',
                trainerId: trainerId,
                athleteId: cobro.athleteId,
                amountArs: cobro.amountArs,
                concept: cobro.concept,
                status: PaymentStatus.paid,
                createdAt: now,
                paidAt: now,
              ),
            );

          case BillingCadence.suelto:
            // Flip all pending one-off charges atomically: a mid-loop failure
            // (network drop / concurrently deleted doc) must not leave the
            // athlete in a half-paid state.
            await repo.markManyPaid(cobro.pendingPaymentIds, now);
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.dashboardCobroRegistrado)),
          );
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.dashboardCobroError)));
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _AvatarInitials(initials: initials, palette: palette),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  showName,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: palette.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${cobro.concept} · ${_cadenceLabel(l10n, cobro.cadence)}',
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
          const SizedBox(width: 8),
          Text(
            '\$${_formatAmount(cobro.amountArs)}',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: palette.accent,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onCobrado,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Text(
                l10n.dashboardCobradoLabel,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: palette.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Add suelto charge sheet ───────────────────────────────────────────────────

class _AddSueltoSheet extends ConsumerStatefulWidget {
  const _AddSueltoSheet({required this.trainerId});
  final String trainerId;

  @override
  ConsumerState<_AddSueltoSheet> createState() => _AddSueltoSheetState();
}

class _AddSueltoSheetState extends ConsumerState<_AddSueltoSheet> {
  String? _selectedAthleteId;
  final _amountController = TextEditingController();
  final _conceptController = TextEditingController();

  /// ART calendar day the charge is due (optional). Only y/m/d are meaningful;
  /// [_submit] expands it to 23:59:59 ART so "vence el 15" is not overdue at
  /// 00:01 of the 15th. `null` → no dueAt (valid: the charge never shows in
  /// Vencidos via dueAt and the overdue-reminder CF skips it).
  DateTime? _dueDate;
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _conceptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final linksAsync = ref.watch(trainerLinksStreamProvider);
    final activeLinks = (linksAsync.valueOrNull ?? const [])
        .where((l) => l.status == TrainerLinkStatus.active)
        .toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.dashboardCobroSueltoTitle,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              letterSpacing: 1.2,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 18),
          // Athlete picker
          Text(
            l10n.dashboardAlumnoLabel,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          if (activeLinks.isEmpty)
            Text(
              l10n.dashboardSinAlumnosActivos,
              style: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
            )
          else
            _AthleteDropdown(
              links: activeLinks,
              selectedId: _selectedAthleteId,
              palette: palette,
              onChanged: (id) => setState(() => _selectedAthleteId = id),
            ),
          const SizedBox(height: 14),
          Text(
            l10n.dashboardMontoArsLabel,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            inputFormatters: [ThousandsSeparatorInputFormatter()],
            style: GoogleFonts.barlow(fontSize: 14, color: palette.textPrimary),
            decoration: InputDecoration(
              hintText: l10n.dashboardMontoHint,
              hintStyle: GoogleFonts.barlow(
                fontSize: 14,
                color: palette.textMuted,
              ),
              filled: true,
              fillColor: palette.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                borderSide: BorderSide(color: palette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                borderSide: BorderSide(color: palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                borderSide: BorderSide(color: palette.accent, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.dashboardConceptoLabel,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _conceptController,
            style: GoogleFonts.barlow(fontSize: 14, color: palette.textPrimary),
            decoration: InputDecoration(
              hintText: l10n.dashboardConceptoHint,
              hintStyle: GoogleFonts.barlow(
                fontSize: 14,
                color: palette.textMuted,
              ),
              filled: true,
              fillColor: palette.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                borderSide: BorderSide(color: palette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                borderSide: BorderSide(color: palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                borderSide: BorderSide(color: palette.accent, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.dashboardVenceElLabel,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: _pickDueDate,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: palette.bg,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                children: [
                  Icon(TreinoIcon.calendar, size: 16, color: palette.textMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _dueDate == null
                          ? l10n.dashboardVenceElHint
                          : _formatDueDate(_dueDate!),
                      style: GoogleFonts.barlow(
                        fontSize: 14,
                        color: _dueDate == null
                            ? palette.textMuted
                            : palette.textPrimary,
                      ),
                    ),
                  ),
                  if (_dueDate != null)
                    Semantics(
                      button: true,
                      label: l10n.dashboardVenceElQuitar,
                      child: GestureDetector(
                        onTap: () => setState(() => _dueDate = null),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            TreinoIcon.close,
                            size: 16,
                            color: palette.textMuted,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving || activeLinks.isEmpty ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: TreinoButtonTokens.foreground(context),
                disabledBackgroundColor: palette.border,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
              child: _saving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: TreinoButtonTokens.foreground(context),
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      l10n.dashboardAgregarCobroLabel,
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.8,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// dd/MM/yyyy — same idiom as payment_format.dart's fmtFecha.
  static String _formatDueDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickDueDate() async {
    // "Today" as an ART calendar day: between 21:00–23:59 ART the UTC day is
    // already tomorrow, so a UTC-derived floor would block picking today.
    final todayArt = argentinaNow();
    final floor = DateTime(todayArt.year, todayArt.month, todayArt.day);
    final initial = _dueDate ?? floor;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(floor) ? floor : initial,
      firstDate: floor,
      lastDate: floor.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _submit() async {
    final l10n = AppL10n.of(context);
    final athleteId = _selectedAthleteId;
    final amountText = _amountController.text.trim();
    final concept = _conceptController.text.trim();

    if (athleteId == null || amountText.isEmpty || concept.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.dashboardCompletaCampos)));
      return;
    }

    final amount = parseGroupedInt(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.dashboardMontoInvalido)));
      return;
    }

    setState(() => _saving = true);

    try {
      final now = DateTime.now().toUtc();
      // dueAt = end of the chosen ART calendar day, as a UTC instant — the
      // same normalization the old generateDuePayments CF used
      // (23:59:59 ART == +3h in UTC). Keeps "vence el 15" from reading as
      // overdue at 00:01 ART of the 15th in the Vencidos bucket and in the
      // notifyOverduePayments reminder CF.
      final dueDate = _dueDate;
      final dueAt = dueDate == null
          ? null
          : DateTime.utc(
              dueDate.year,
              dueDate.month,
              dueDate.day,
              23,
              59,
              59,
            ).add(argentinaUtcOffset);
      await ref.read(paymentRepositoryProvider).add(
            Payment(
              id: '',
              trainerId: widget.trainerId,
              athleteId: athleteId,
              amountArs: amount,
              concept: concept,
              status: PaymentStatus.pending,
              createdAt: now,
              dueAt: dueAt,
            ),
          );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.dashboardCobroSueltoAgregado)),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.dashboardGuardarError)));
      }
    }
  }
}

/// Test-only harness that renders `_AddSueltoSheet` directly, bypassing the
/// dashboard + bottom-sheet plumbing. Exported for widget tests only.
///
/// @visibleForTesting
class AddSueltoSheetTestHarness extends StatelessWidget {
  const AddSueltoSheetTestHarness({super.key, required this.trainerId});

  final String trainerId;

  @override
  Widget build(BuildContext context) => _AddSueltoSheet(trainerId: trainerId);
}

/// Dropdown widget to pick an active athlete by name.
class _AthleteDropdown extends ConsumerWidget {
  const _AthleteDropdown({
    required this.links,
    required this.selectedId,
    required this.palette,
    required this.onChanged,
  });

  final List<TrainerLink> links;
  final String? selectedId;
  final AppPalette palette;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    return DropdownButtonFormField<String>(
      initialValue: selectedId,
      hint: Text(
        l10n.dashboardSeleccionaAlumnoHint,
        style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
      ),
      dropdownColor: palette.bgCard,
      style: GoogleFonts.barlow(fontSize: 14, color: palette.textPrimary),
      decoration: InputDecoration(
        filled: true,
        fillColor: palette.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: palette.accent, width: 1.5),
        ),
      ),
      items: links.map((link) {
        final profileAsync = ref.watch(
          userPublicProfileProvider(link.athleteId),
        );
        final rawName = profileAsync.valueOrNull?.displayName ?? '';
        final showName = rawName.isEmpty || _looksLikeUid(rawName)
            ? '${l10n.dashboardAlumnoFallback} (${link.athleteId.substring(0, 6)})'
            : rawName;
        return DropdownMenuItem<String>(
          value: link.athleteId,
          child: Text(showName),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }
}

// ── Placeholder card (for sections not yet wired) ─────────────────────────────

class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard({required this.palette, required this.message});
  final AppPalette palette;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Text(
        message,
        style: GoogleFonts.barlow(
          fontWeight: FontWeight.w400,
          fontSize: 13,
          color: palette.textMuted,
        ),
      ),
    );
  }
}

// ── Bottom actions (Invitar / Asignar) ────────────────────────────────────────

class _BottomActions extends StatelessWidget {
  const _BottomActions();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    // "Invitar alumno" removed (#397): the trainer↔athlete link is
    // athlete-initiated only (trainer_link_repository.dart product convention),
    // there is no invite infra, and the web equivalent was already removed. The
    // stub only showed a "próximamente" SnackBar, so it's dropped rather than
    // left as a dead CTA. "Asignar rutina" now spans the full width.
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () => context.go('/coach?tab=alumnos'),
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: TreinoButtonTokens.foreground(context),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
        ),
        child: Text(
          l10n.dashboardAsignarRutinaLabel,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _weekdayName(AppL10n l10n, int weekday) {
  switch (weekday) {
    case DateTime.monday:
      return l10n.dashboardWeekday1;
    case DateTime.tuesday:
      return l10n.dashboardWeekday2;
    case DateTime.wednesday:
      return l10n.dashboardWeekday3;
    case DateTime.thursday:
      return l10n.dashboardWeekday4;
    case DateTime.friday:
      return l10n.dashboardWeekday5;
    case DateTime.saturday:
      return l10n.dashboardWeekday6;
    default:
      return l10n.dashboardWeekday7;
  }
}

String _monthName(AppL10n l10n, int month) {
  switch (month) {
    case 1:
      return l10n.dashboardMonth1;
    case 2:
      return l10n.dashboardMonth2;
    case 3:
      return l10n.dashboardMonth3;
    case 4:
      return l10n.dashboardMonth4;
    case 5:
      return l10n.dashboardMonth5;
    case 6:
      return l10n.dashboardMonth6;
    case 7:
      return l10n.dashboardMonth7;
    case 8:
      return l10n.dashboardMonth8;
    case 9:
      return l10n.dashboardMonth9;
    case 10:
      return l10n.dashboardMonth10;
    case 11:
      return l10n.dashboardMonth11;
    default:
      return l10n.dashboardMonth12;
  }
}

String _formatHeaderDate(AppL10n l10n, DateTime dt) {
  return '${_weekdayName(l10n, dt.weekday)} ${dt.day} ${_monthName(l10n, dt.month)}';
}

String _formatTime(DateTime dt) {
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

String _formatDateLabel(AppL10n l10n, DateTime dt) {
  // QA-COA-003: dt is wall-clock UTC (ADR-7); use wall-clock "now" so a session
  // tomorrow isn't labelled "Hoy" between 21:00-23:59 ART.
  final now = nowWall();
  final isToday = _isSameLocalDay(dt, now);
  final isTomorrow = _isSameLocalDay(dt, now.add(const Duration(days: 1)));
  if (isToday) return l10n.dashboardDateToday;
  if (isTomorrow) return l10n.dashboardDateTomorrow;
  final dd = dt.day.toString().padLeft(2, '0');
  final mm = dt.month.toString().padLeft(2, '0');
  return '$dd/$mm';
}

bool _isSameLocalDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _initials(String name) {
  final clean = name.trim();
  if (clean.isEmpty) return '·';
  final parts = clean.split(RegExp(r'\s+'));
  if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
  if (parts[0].length >= 2) {
    return parts[0].substring(0, 2).toUpperCase();
  }
  return parts[0].toUpperCase();
}

/// Heuristic to detect a UID stored in athleteDisplayName from pre-backfill
/// bookings — used as last-resort fallback in the row to avoid displaying
/// the raw UID. The proper fix is the live Firestore stream (see
/// trainer_day_detail_sheet.dart).
bool _looksLikeUid(String s) {
  if (s.length < 20) return false;
  // Firebase UIDs are 28-char alphanumeric. If it contains no spaces and is
  // long + mostly alphanumeric, treat as UID.
  if (s.contains(' ')) return false;
  final alphaNumeric = RegExp(r'^[a-zA-Z0-9]+$');
  return alphaNumeric.hasMatch(s);
}

TrainerAppointmentsKey _appointmentsKey(String trainerId) {
  // QA-HOME-009: misma ventana rodante que la agenda (helper compartido).
  final window = rollingAppointmentWindow(DateTime.now().toUtc());
  return TrainerAppointmentsKey(
    trainerId: trainerId,
    fromDate: window.from,
    toDate: window.to,
  );
}
