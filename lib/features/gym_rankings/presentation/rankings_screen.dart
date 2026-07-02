import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../auth/application/auth_providers.dart';
import '../../gyms/domain/gym.dart' show kNoGymId;
import '../../profile/application/ranking_optin_controller_provider.dart';
import '../../profile/application/user_providers.dart' show userProfileProvider;
import '../../profile/application/user_public_profile_providers.dart'
    show userPublicProfileProvider;
import '../../profile/domain/user_public_profile.dart';
import '../application/ranking_providers.dart';
import '../domain/ranking_dimension.dart';

/// Per-gym rankings screen — 3 dimensions (Rachas / Volumen / Lifts, lifts
/// sub-split squat/bench/deadlift) for the current athlete's gym.
///
/// Placement: `/profile/rankings` is RETIRED as a pushed route and now
/// redirects to `/workout?tab=rankings` (design `sdd/rankings-v2/design`
/// AD-3, Phase 3 cleanup). The PRIMARY placement is the second page of the
/// athlete Entrenar tab (`WorkoutScreen`'s `_RankingsPage`, AD-1/AD-2). This
/// class is no longer mounted by the router — it is kept as a widget-test
/// harness (`rankings_screen_test.dart`) that exercises the same
/// [RankingsBody] both hosts render, so gating/body logic is verified once.
class RankingsScreen extends StatelessWidget {
  const RankingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const RankingsBody();
}

/// The rankings surface body — gym resolution, opt-in gate, leaderboards,
/// and the slim page header (design AD-7). Composed directly by
/// [RankingsScreen] (pushed-route placement) and by `WorkoutScreen`'s
/// `_RankingsPage` (tab placement, the primary one as of this slice).
///
/// The screen resolves the athlete's `gymId` from [userProfileProvider] —
/// while that resolves, a loading spinner is shown. An athlete with no gym
/// (`null`/[kNoGymId]) sees a dedicated "no gym" state instead of empty
/// leaderboards, since rankings are inherently gym-scoped (spec
/// `gym-rankings` — Gym Scoping and No-Gym Exclusion), and this precedes the
/// opt-in gate below regardless of `rankingOptIn` (spec `gym-rankings` —
/// No-Gym Precedence Over Opt-In Gate).
///
/// Opt-in gate (design AD-6, spec `gym-rankings` — Opt-In Gate on the
/// Rankings Surface): once a gym is confirmed, the screen watches
/// `userPublicProfileProvider(myUid).select((p) => p?.rankingOptIn ?? false)`
/// — `select`-scoped so the gate does NOT rebuild on every ranking-metric
/// counter tick, only on the opt-in bit flipping. `false` renders the
/// invitation state (CTA to enable); `true` renders the leaderboards
/// ([_RankingsBody]) with an accessible disable affordance in the header
/// (design AD-7, spec `gym-rankings` — Opt-In Toggle Lives on the Rankings
/// Surface). `ProfileScreen` does not host a separate entry point.
///
/// AD-4 self-heal: [RankingOptInControllerBase.syncGymIfDesynced] is invoked
/// once via `ref.read` on first build (not `watch` — this is a fire-and-
/// forget repair, not a value the widget renders from) so already-opted-in
/// athletes whose public `gymId` drifted get silently repaired.
class RankingsBody extends ConsumerStatefulWidget {
  const RankingsBody({super.key});

  @override
  ConsumerState<RankingsBody> createState() => _RankingsBodyState();
}

class _RankingsBodyState extends ConsumerState<RankingsBody> {
  MainLiftTab _liftTab = MainLiftTab.squat;
  bool _syncedOnce = false;

  void _syncGymOnce(String uid) {
    if (_syncedOnce || uid.isEmpty) return;
    _syncedOnce = true;
    // AD-4: fire-and-forget, best-effort — the controller itself swallows
    // failures. `ref.read` (not `watch`) — this is an action, not a value
    // this widget renders from.
    ref.read(rankingOptInControllerProvider).syncGymIfDesynced(uid);
  }

  Future<void> _confirmDisable(String uid) async {
    final palette = AppPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'DESACTIVAR RANKINGS',
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: palette.textPrimary,
          ),
        ),
        content: Text(
          'Si desactivás los rankings, tus métricas se borran de los '
          'tableros. ¿Seguro?',
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
              'Desactivar',
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
    await ref.read(rankingOptInControllerProvider).disableRankingOptIn(uid);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final myUid = ref.watch(authStateChangesProvider).valueOrNull?.uid ?? '';
    final profileAsync = ref.watch(userProfileProvider);
    final rankingOptIn = ref.watch(
      userPublicProfileProvider(myUid)
          .select((async) => async.valueOrNull?.rankingOptIn ?? false),
    );

    if (myUid.isNotEmpty && rankingOptIn) {
      _syncGymOnce(myUid);
    }

    return Column(
      children: [
        // ── Header ──────────────────────────────────────────────────────
        // AD-7: slim `RANKINGS` title + disable affordance (leaderboards
        // state only) — replaces the v1 back-button header now that this
        // surface is a tab page, not exclusively a pushed route.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Text(
                'RANKINGS',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  color: palette.textPrimary,
                ),
              ),
              const Spacer(),
              if (rankingOptIn)
                IconButton(
                  key: const Key('rankings_disable_affordance'),
                  onPressed: () => _confirmDisable(myUid),
                  icon: Icon(TreinoIcon.close,
                      size: 20, color: palette.textMuted),
                  tooltip: 'Desactivar rankings',
                ),
            ],
          ),
        ),

        // ── Body ────────────────────────────────────────────────────────
        Expanded(
          child: profileAsync.when(
            loading: () => _LoadingBlock(palette: palette),
            error: (_, __) => _ErrorBlock(palette: palette),
            data: (profile) {
              final gymId = profile?.gymId;
              if (gymId == null || gymId.isEmpty || gymId == kNoGymId) {
                return _NoGymState(palette: palette);
              }
              if (!rankingOptIn) {
                return _InvitationState(myUid: myUid, palette: palette);
              }
              return _RankingsBody(
                gymId: gymId,
                myUid: myUid,
                palette: palette,
                liftTab: _liftTab,
                onLiftTabChanged: (tab) => setState(() => _liftTab = tab),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Opted-out invitation state (design AD-6, spec `gym-rankings` — Opt-In
/// Toggle Lives on the Rankings Surface). Renders a prominent `ACTIVAR
/// RANKINGS` CTA that calls [RankingOptInControllerBase.enableRankingOptIn].
/// The success path needs no manual navigation: [_OptInGate] watches the
/// same live provider this write targets, so the surface swaps to
/// leaderboards the instant the write lands.
class _InvitationState extends ConsumerStatefulWidget {
  const _InvitationState({required this.myUid, required this.palette});

  final String myUid;
  final AppPalette palette;

  @override
  ConsumerState<_InvitationState> createState() => _InvitationStateState();
}

class _InvitationStateState extends ConsumerState<_InvitationState> {
  bool _enabling = false;

  Future<void> _enable() async {
    setState(() => _enabling = true);
    try {
      await ref
          .read(rankingOptInControllerProvider)
          .enableRankingOptIn(widget.myUid);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No pudimos activar los rankings. Probá de nuevo.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _enabling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Center(
      child: Padding(
        key: const Key('rankings_invitation_state'),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(TreinoIcon.ranking, size: 32, color: palette.accent),
            const SizedBox(height: 14),
            Text(
              'SUMATE A LOS RANKINGS',
              textAlign: TextAlign.center,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Compará tus rachas, tu volumen y tus levantamientos con la '
              'gente de tu gym. Activá los rankings para aparecer.',
              textAlign: TextAlign.center,
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: 14,
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _enabling ? null : _enable,
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.bg,
                  disabledBackgroundColor:
                      palette.accent.withValues(alpha: 0.5),
                  disabledForegroundColor: palette.bg,
                  shape: const StadiumBorder(),
                  padding: EdgeInsets.zero,
                ),
                child: _enabling
                    ? SizedBox(
                        key: const Key('rankings_optin_enabling'),
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(palette.bg),
                        ),
                      )
                    : Text(
                        'ACTIVAR RANKINGS',
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          letterSpacing: 1.0,
                          color: palette.bg,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum MainLiftTab { squat, bench, deadlift }

extension on MainLiftTab {
  RankingDimension get dimension {
    switch (this) {
      case MainLiftTab.squat:
        return RankingDimension.squat;
      case MainLiftTab.bench:
        return RankingDimension.bench;
      case MainLiftTab.deadlift:
        return RankingDimension.deadlift;
    }
  }

  String get label {
    switch (this) {
      case MainLiftTab.squat:
        return 'SENTADILLA';
      case MainLiftTab.bench:
        return 'BANCA';
      case MainLiftTab.deadlift:
        return 'PESO MUERTO';
    }
  }
}

class _RankingsBody extends ConsumerWidget {
  const _RankingsBody({
    required this.gymId,
    required this.myUid,
    required this.palette,
    required this.liftTab,
    required this.onLiftTabChanged,
  });

  final String gymId;
  final String myUid;
  final AppPalette palette;
  final MainLiftTab liftTab;
  final ValueChanged<MainLiftTab> onLiftTabChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liftProvider = switch (liftTab) {
      MainLiftTab.squat => squatLeaderboardProvider(gymId),
      MainLiftTab.bench => benchLeaderboardProvider(gymId),
      MainLiftTab.deadlift => deadliftLeaderboardProvider(gymId),
    };

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DimensionSection(
            sectionKey: const Key('rankings_section_streak'),
            emptyKey: const Key('rankings_empty_streak'),
            title: 'RACHAS',
            icon: TreinoIcon.streak,
            myUid: myUid,
            async: ref.watch(streakLeaderboardProvider(gymId)),
            dimension: RankingDimension.streak,
          ),
          const SizedBox(height: 20),
          _DimensionSection(
            sectionKey: const Key('rankings_section_volume'),
            emptyKey: const Key('rankings_empty_volume'),
            title: 'VOLUMEN',
            icon: TreinoIcon.chartBar,
            myUid: myUid,
            async: ref.watch(volumeLeaderboardProvider(gymId)),
            dimension: RankingDimension.volume,
          ),
          const SizedBox(height: 20),
          Row(
            key: const Key('rankings_section_lifts'),
            children: [
              Icon(TreinoIcon.dumbbell, size: 16, color: palette.textMuted),
              const SizedBox(width: 8),
              Text(
                'LIFTS',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 1.4,
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _LiftTabBar(selected: liftTab, onChanged: onLiftTabChanged),
          const SizedBox(height: 12),
          _DimensionSection(
            sectionKey: Key('rankings_section_lift_${liftTab.name}'),
            emptyKey: Key('rankings_empty_${liftTab.name}'),
            title: null,
            icon: null,
            myUid: myUid,
            async: ref.watch(liftProvider),
            dimension: liftTab.dimension,
          ),
        ],
      ),
    );
  }
}

class _LiftTabBar extends StatelessWidget {
  const _LiftTabBar({required this.selected, required this.onChanged});

  final MainLiftTab selected;
  final ValueChanged<MainLiftTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        for (final tab in MainLiftTab.values) ...[
          if (tab != MainLiftTab.values.first) const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              key: Key('rankings_lift_tab_${tab.name}'),
              onTap: () => onChanged(tab),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: tab == selected
                      ? palette.accent.withValues(alpha: 0.15)
                      : palette.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: tab == selected
                        ? palette.accent.withValues(alpha: 0.5)
                        : palette.border,
                  ),
                ),
                child: Text(
                  tab.label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1.0,
                    color: tab == selected ? palette.accent : palette.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DimensionSection extends StatelessWidget {
  const _DimensionSection({
    required this.sectionKey,
    required this.emptyKey,
    required this.title,
    required this.icon,
    required this.myUid,
    required this.async,
    required this.dimension,
  });

  final Key sectionKey;
  final Key emptyKey;
  final String? title;
  final IconData? icon;
  final String myUid;
  final AsyncValue<List<UserPublicProfile>> async;
  final RankingDimension dimension;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      key: sectionKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: palette.textMuted),
                const SizedBox(width: 8),
              ],
              Text(
                title!,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 1.4,
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        async.when(
          loading: () => _LoadingBlock(palette: palette),
          error: (_, __) => _ErrorBlock(palette: palette),
          data: (profiles) {
            if (profiles.isEmpty) {
              return _EmptyLeaderboard(emptyKey: emptyKey, palette: palette);
            }
            return _LeaderboardList(
              profiles: profiles,
              myUid: myUid,
              dimension: dimension,
              palette: palette,
            );
          },
        ),
      ],
    );
  }
}

class _LeaderboardList extends StatelessWidget {
  const _LeaderboardList({
    required this.profiles,
    required this.myUid,
    required this.dimension,
    required this.palette,
  });

  final List<UserPublicProfile> profiles;
  final String myUid;
  final RankingDimension dimension;
  final AppPalette palette;

  num _metricValue(UserPublicProfile profile) {
    switch (dimension) {
      case RankingDimension.streak:
        return profile.racha ?? 0;
      case RankingDimension.volume:
        return profile.lifetimeVolumeKg;
      case RankingDimension.squat:
        return profile.bestSquatKg ?? 0;
      case RankingDimension.bench:
        return profile.bestBenchKg ?? 0;
      case RankingDimension.deadlift:
        return profile.bestDeadliftKg ?? 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < profiles.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 1, color: palette.border, indent: 14, endIndent: 14),
            _LeaderboardRow(
              rank: i + 1,
              profile: profiles[i],
              value: _metricValue(profiles[i]),
              isMe: profiles[i].uid == myUid,
              palette: palette,
            ),
          ],
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({
    required this.rank,
    required this.profile,
    required this.value,
    required this.isMe,
    required this.palette,
  });

  final int rank;
  final UserPublicProfile profile;
  final num value;
  final bool isMe;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('rankings_row_${profile.uid}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isMe ? palette.accent.withValues(alpha: 0.08) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: palette.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              profile.displayName ?? '—',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.barlow(
                fontWeight: isMe ? FontWeight.w700 : FontWeight.w400,
                fontSize: 14,
                color: isMe ? palette.accent : palette.textPrimary,
              ),
            ),
          ),
          Text(
            _formatValue(value),
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: isMe ? palette.accent : palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatValue(num value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(1);
  }
}

class _EmptyLeaderboard extends StatelessWidget {
  const _EmptyLeaderboard({required this.emptyKey, required this.palette});

  final Key emptyKey;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: emptyKey,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        'Todavía nadie de tu gym se sumó a este ranking.',
        textAlign: TextAlign.center,
        style: GoogleFonts.barlow(
          fontWeight: FontWeight.w400,
          fontSize: 14,
          color: palette.textMuted,
        ),
      ),
    );
  }
}

class _NoGymState extends StatelessWidget {
  const _NoGymState({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        key: const Key('rankings_no_gym_state'),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(TreinoIcon.gym, size: 32, color: palette.textMuted),
            const SizedBox(height: 14),
            Text(
              'Sumate a un gym desde tu perfil para ver rankings.',
              textAlign: TextAlign.center,
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: 14,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        'No pudimos cargar el ranking. Intentá de nuevo.',
        textAlign: TextAlign.center,
        style: GoogleFonts.barlow(
          fontWeight: FontWeight.w400,
          fontSize: 14,
          color: palette.textMuted,
        ),
      ),
    );
  }
}
