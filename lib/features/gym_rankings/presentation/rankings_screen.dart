import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
/// Placement (this slice): `/profile/rankings`, sibling of
/// `edit-personal`/`gym`/`routines` — relocation into the Entrenar tab is a
/// LATER slice (design `sdd/rankings-v2/design` AD-1/AD-2, Slice 2).
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
/// invitation state (CTA to enable); `true` renders the existing
/// [_RankingsBody] leaderboards, unchanged. The opt-in toggle itself now
/// lives directly on this surface (invitation CTA here; the disable
/// affordance is added in a later slice, AD-7) — `ProfileScreen` no longer
/// hosts a separate entry point.
class RankingsScreen extends ConsumerStatefulWidget {
  const RankingsScreen({super.key});

  @override
  ConsumerState<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends ConsumerState<RankingsScreen> {
  MainLiftTab _liftTab = MainLiftTab.squat;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final myUid = ref.watch(authStateChangesProvider).valueOrNull?.uid ?? '';
    final profileAsync = ref.watch(userProfileProvider);

    return Column(
      children: [
        // ── Header ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: GestureDetector(
            onTap: () => context.pop(),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Icon(TreinoIcon.back, size: 20, color: palette.textPrimary),
                const SizedBox(width: 14),
                Text(
                  'RANKINGS',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
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
              return _OptInGate(
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

/// AD-6 gating wrapper — branches invitation state vs leaderboards based on
/// the athlete's OWN `rankingOptIn` (read from the PUBLIC profile, not the
/// private one — see [RankingsScreen] doc). Lives between the no-gym guard
/// (above, higher precedence) and [_RankingsBody] (unchanged).
class _OptInGate extends ConsumerWidget {
  const _OptInGate({
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
    final rankingOptIn = ref.watch(
      userPublicProfileProvider(myUid)
          .select((async) => async.valueOrNull?.rankingOptIn ?? false),
    );

    if (!rankingOptIn) {
      return _InvitationState(myUid: myUid, palette: palette);
    }

    return _RankingsBody(
      gymId: gymId,
      myUid: myUid,
      palette: palette,
      liftTab: liftTab,
      onLiftTabChanged: onLiftTabChanged,
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
