import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_palette.dart';
import '../../core/widgets/treino_icon.dart';
import '../../l10n/app_l10n.dart';
import '../coach/presentation/trainer_dashboard_tab.dart';
import '../notifications/presentation/permission_gate.dart';
import '../profile/application/user_providers.dart';
import '../profile/domain/user_role.dart';
import '../workout/application/assigned_routine_providers.dart';
import '../workout/application/session_providers.dart';
import '../workout/application/user_routines_providers.dart';
import '../workout/domain/session.dart';
import '../workout/domain/set_log.dart';
import '../workout/presentation/widgets/resume_session_modal.dart';
import 'widgets/empezar_entrenamiento_card.dart';
import 'widgets/esta_semana_card.dart';
import 'widgets/home_cta_button.dart';
import 'widgets/home_header.dart';

/// Role-aware home screen.
///
/// - Trainer → [TrainerDashboardTab] (mirrors docs/app-trainer/screens/dashboard).
/// - Athlete → existing athlete home (header + Empezar + Esta semana + resume
///   session modal listener).
/// - Loading → empty surface (cheap, no spinner — matches `_CoachLoadingView`
///   pattern in [CoachScreen]).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserRole? role = ref.watch(
      userProfileProvider.select((async) => async.valueOrNull?.role),
    );

    // Default to athlete view while role is loading. Athletes are the
    // dominant user, and the athlete home is safe to render without role
    // confirmation (HomeHeader gracefully handles a null profile). Trainers
    // may see a brief athlete flicker before their dashboard mounts — an
    // acceptable trade for not stalling the 99% common case.
    return Stack(
      children: [
        role == UserRole.trainer
            ? const TrainerDashboardTab()
            : const _AthleteHome(),
        // REQ-PN-PERM-001: session-scoped permission prompt.
        // Renders SizedBox.shrink() — zero layout impact. ADR-PN-012.
        const PermissionGate(),
      ],
    );
  }
}

/// Athlete home — original [HomeScreen] body extracted intact so role split
/// is purely additive.
class _AthleteHome extends ConsumerWidget {
  const _AthleteHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);

    // Resume-on-reopen listener (REQ-SESSION-RESUME-002 / Decision 12).
    ref.listen<AsyncValue<({Session session, List<SetLog> setLogs})?>>(
      activeSessionForUidProvider,
      (prev, next) {
        // Dedupe by stable session id, not identity. The provider returns a
        // fresh Dart record on every run, so `identical` never matches and the
        // resume dialog would re-stack whenever currentUidProvider's auth
        // stream re-emits the same active session.
        if (prev?.valueOrNull?.session.id == next.valueOrNull?.session.id) {
          return;
        }
        _maybeShowResumePrompt(context, ref, next);
      },
    );

    final Widget headerOrSkeleton = profileAsync.when(
      data: (profile) => HomeHeader(profile: profile),
      loading: () => const _HomeHeaderSkeleton(),
      error: (_, __) => const HomeHeader(profile: null),
    );

    // Gate the hero "Empezar" card behind real routine data so a brand-new
    // athlete never lands on a hardcoded fake workout (finding 5). We treat
    // the athlete as first-run only once BOTH their self-created routines and
    // their trainer-assigned plans have resolved to empty. While either is
    // loading or errors, fall back to the existing card (no spinner flash,
    // and we never hide a real workout behind a transient empty read).
    final uid = ref.watch(currentUidProvider) ?? '';
    final hasNoRoutine = uid.isEmpty
        ? false
        : _isEmptyData(ref.watch(userCreatedRoutinesProvider(uid))) &&
            _isEmptyData(ref.watch(assignedRoutinesProvider(uid)));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ListView(
        // + bottom inset: the floating bar overlays the body (extendBody),
        // so the last item needs room to scroll out from behind it.
        padding: EdgeInsets.fromLTRB(
            0, 20, 0, 20 + MediaQuery.paddingOf(context).bottom),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          headerOrSkeleton,
          const SizedBox(height: 20),
          if (hasNoRoutine)
            const _AthleteFirstRunCard()
          else
            const EmpezarEntrenamientoCard(),
          const SizedBox(height: 12),
          const EstaSemanaCard(),
        ],
      ),
    );
  }
}

/// True only when [async] has resolved to an empty list. Loading and error
/// states return false so the caller keeps showing the existing workout card
/// instead of a premature first-run empty state (finding 5).
bool _isEmptyData(AsyncValue<List<Object?>> async) =>
    async.valueOrNull?.isEmpty ?? false;

/// First-run empty state shown on Home when the athlete has no self-created
/// routine and no trainer-assigned plan. Replaces the hardcoded fake workout
/// card with an honest onboarding surface and two CTAs (finding 5).
class _AthleteFirstRunCard extends StatelessWidget {
  const _AthleteFirstRunCard();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.homeAthleteFirstRunTitle,
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: palette.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.homeAthleteFirstRunBody,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: 18),
            HomeCTAButton(
              label: l10n.homeAthleteFirstRunCreateCta,
              leadingIcon: TreinoIcon.plus,
              onPressed: () => context.push('/workout/my-routine-editor'),
            ),
            const SizedBox(height: 10),
            // Secondary CTA: route to the Coach tab where athletes browse and
            // request a trainer.
            OutlinedButton.icon(
              onPressed: () => context.go('/coach'),
              icon: Icon(TreinoIcon.search, size: 16, color: palette.accent),
              label: Text(
                l10n.homeAthleteFirstRunFindTrainerCta,
                style: TextStyle(color: palette.accent),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                side: BorderSide(color: palette.accent.withValues(alpha: 0.6)),
                shape: const StadiumBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _maybeShowResumePrompt(
  BuildContext context,
  WidgetRef ref,
  AsyncValue<({Session session, List<SetLog> setLogs})?> next,
) {
  final record = next.valueOrNull;
  if (record == null) return;
  final session = record.session;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => ResumeSessionModal(
        session: session,
        onContinue: () {
          Navigator.of(dialogCtx, rootNavigator: true).pop();
          context.push('/workout/session/resume/${session.id}');
        },
        onDiscard: () async {
          final repo = ref.read(sessionRepositoryProvider);
          await repo.finish(
            uid: session.uid,
            sessionId: session.id,
            finishedAt: DateTime.now(),
            totalVolumeKg: _sumVolume(record.setLogs),
            durationMin: _elapsedMin(session.startedAt),
          );
          // _AthleteHome may have been disposed during the finish() write
          // (user navigated away). Invalidating through a torn-down ref throws,
          // so guard on the host context before touching ref again.
          if (!context.mounted) return;
          if (dialogCtx.mounted) {
            Navigator.of(dialogCtx, rootNavigator: true).pop();
          }
          ref.invalidate(activeSessionForUidProvider);
        },
      ),
    );
  });
}

double _sumVolume(List<SetLog> logs) =>
    logs.fold<double>(0, (acc, l) => acc + l.reps * l.weightKg);

int _elapsedMin(DateTime startedAt) {
  final secs = DateTime.now().difference(startedAt).inSeconds;
  if (secs <= 0) return 1;
  return (secs + 59) ~/ 60;
}

/// Private placeholder that occupies the same 56 px height as [HomeHeader]
/// during [AsyncLoading], preventing a layout jump (REQ-HOME-PROVIDER-003).
class _HomeHeaderSkeleton extends StatelessWidget {
  const _HomeHeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    // Announce the loading state so screen readers don't land on a silent,
    // empty 56px surface while the profile header resolves.
    //
    // Sin TreinoShimmer a propósito (TREINO Motion PR2): este skeleton es un
    // spacer transparente sin cajas pintadas — con BlendMode.srcATop el
    // barrido no pintaría ni un píxel, pero el controller correría igual
    // (createShader + ShaderMaskLayer por frame). Trabajo muerto.
    return Semantics(
      label: l10n.commonLoading,
      liveRegion: true,
      child: const SizedBox(height: 56),
    );
  }
}
