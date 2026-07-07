import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../auth/application/auth_providers.dart';
import '../../chat/application/chat_providers.dart';
import '../../workout/application/user_routines_providers.dart';
import '../application/post_providers.dart';
import '../application/public_profile_providers.dart';
import '../domain/friendship.dart';
import '../domain/friendship_status.dart';
import 'widgets/post_card.dart';
import 'widgets/public_profile_follow_button.dart';
import 'widgets/public_profile_hero.dart';
import 'widgets/public_profile_stats_row.dart';
import '../../workout/presentation/widgets/routine_card.dart';

/// Which tab is selected inside the public profile screen.
/// Private to this file — the screen and `_ProfileTabPills` are the only
/// consumers (REQ-PROFILE-TABS-001 forbids cross-feature reuse).
enum _ProfileTab { rutinas, actividad }

/// Per-target tab state. Family keyed by `targetUid` so two simultaneous
/// profile visits don't share state.
final _profileTabProvider =
    StateProvider.autoDispose.family<_ProfileTab, String>(
  (ref, _) => _ProfileTab.rutinas,
);

/// Public profile screen for a non-self user. Watches a single composed
/// view-model provider and routes data / loading / error to subtrees.
class PublicProfileScreen extends ConsumerWidget {
  const PublicProfileScreen({super.key, required this.targetUid});

  final String targetUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final viewAsync = ref.watch(publicProfileViewProvider(targetUid));

    // Transparent Scaffold + AppBar so the screen still composites over the
    // shell's AppBackground, while providing an on-screen back affordance
    // (mirrors TrainerPublicProfileScreen). Without this the pushed sub-route
    // is a navigational dead-end — the bottom tab bar replaces the stack
    // rather than popping.
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(TreinoIcon.back, color: palette.textPrimary),
          tooltip: l10n.commonBack,
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/feed'),
        ),
      ),
      body: viewAsync.when(
        data: (view) {
          final viewerUid =
              ref.watch(authStateChangesProvider).valueOrNull?.uid ?? '';
          // Privacy gate — Instagram-style. When the target profile is
          // private AND the viewer is neither the owner nor an ACCEPTED
          // follower, hide detailed content (stats numbers, rutinas, actividad).
          // Header (name / avatar / gym) and the SEGUIR button stay visible so
          // the viewer can still send a follow request.
          final isAcceptedFollower =
              view.friendship?.status.name == 'accepted';
          final gated = !view.isSelf && !view.isPublic && !isAcceptedFollower;
          // Bottom inset so the last post/routine clears the floating
          // TreinoBottomBar (WhatsApp-style: extendBody + translucent pill).
          // Composition: pill height (72) + top margin (8) + bottom safe
          // area + a small breathing gap. Without this the last card sits
          // behind the bar and can't be fully read even on scroll.
          final bottomInset =
              MediaQuery.paddingOf(context).bottom + 88;
          return SingleChildScrollView(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  image: true,
                  label: l10n.a11yAvatarLabel(view.authorDisplayName),
                  child: PublicProfileHero(view: view),
                ),
                const SizedBox(height: 20),
                if (!view.isSelf) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: PublicProfileFollowButton(
                            friendship: view.friendship,
                            viewerUid: viewerUid,
                            targetUid: targetUid,
                            targetIsPublic: view.isPublic,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MessageButton(
                            friendship: view.friendship,
                            viewerUid: viewerUid,
                            targetUid: targetUid,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                if (gated) ...[
                  const _PrivateProfileNotice(),
                  const SizedBox(height: 20),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: PublicProfileStatsRow(
                      workoutsCount: view.workoutsCount,
                      racha: view.racha,
                      followersCount: view.followersCount,
                      followingCount: view.followingCount,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _ProfileTabPills(targetUid: targetUid),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _ProfileTabBody(targetUid: targetUid),
                  ),
                  const SizedBox(height: 20),
                ],
              ],
            ),
          );
        },
        loading: () => Center(
          child: Semantics(
            label: l10n.commonLoading,
            child: CircularProgressIndicator(color: palette.accent),
          ),
        ),
        error: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Center(
            child: Semantics(
              liveRegion: true,
              label: l10n.publicProfileLoadErrorA11y,
              child: Text(
                l10n.publicProfileLoadErrorA11y,
                style: GoogleFonts.barlow(
                  fontSize: 14,
                  color: palette.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Notice shown when the target profile is private and the viewer is not
/// an accepted follower. Renders a lock icon + short explanatory copy.
class _PrivateProfileNotice extends StatelessWidget {
  const _PrivateProfileNotice();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
      child: Column(
        children: [
          Icon(TreinoIcon.lock, size: 32, color: palette.textMuted),
          const SizedBox(height: 12),
          Text(
            'Perfil privado', // i18n: Fase W2
            style: GoogleFonts.barlow(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Seguí a esta persona para ver su actividad y sus rutinas públicas.', // i18n: Fase W2
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(
              fontSize: 13,
              color: palette.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// MENSAJE pill on the public profile screen. Gated by friendship state
/// (Option B — Instagram DMs model): only enabled when the viewer and the
/// target are accepted followers of each other.
///
/// When enabled, tapping the pill calls `ChatRepository.getOrCreate` and
/// pushes `/coach/chat/{chatId}?other={targetUid}` — the same route already
/// used by `chat_list_screen.dart`, `athlete_coach_view.dart` and
/// `athlete_detail_screen.dart`. The route is misnamed "/coach/" for
/// historical reasons but it's actually generic between any two uids.
class _MessageButton extends ConsumerStatefulWidget {
  const _MessageButton({
    required this.friendship,
    required this.viewerUid,
    required this.targetUid,
  });

  final Friendship? friendship;
  final String viewerUid;
  final String targetUid;

  @override
  ConsumerState<_MessageButton> createState() => _MessageButtonState();
}

class _MessageButtonState extends ConsumerState<_MessageButton> {
  bool _busy = false;

  bool get _isAcceptedFriend =>
      widget.friendship?.status == FriendshipStatus.accepted;

  Future<void> _onTap() async {
    if (_busy || !_isAcceptedFriend) return;
    setState(() => _busy = true);
    // Capture the router + messenger BEFORE the await — same protocol as
    // PublicProfileFollowButton: the route may pop mid-write, after which
    // `context` is unmounted. Router + root messenger both survive disposal.
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final chat = await ref
          .read(chatRepositoryProvider)
          .getOrCreate(selfId: widget.viewerUid, otherId: widget.targetUid);
      router.push('/coach/chat/${chat.chatId}?other=${widget.targetUid}');
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'No pudimos abrir el chat. Probá de nuevo.', // i18n: Fase W2
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final enabled = _isAcceptedFriend && !_busy;
    final textColor = enabled ? palette.textPrimary : palette.textMuted;
    return Semantics(
      button: true,
      enabled: enabled,
      label: enabled
          ? 'Mensaje' // i18n: Fase W2
          : l10n.publicProfileMessageDisabledA11y,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: enabled ? 1.0 : 0.6,
          child: GestureDetector(
            onTap: enabled ? _onTap : null,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: palette.border, width: 1),
              ),
              child: Center(
                child: _busy
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.textMuted,
                        ),
                      )
                    : Text(
                        'MENSAJE',
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          letterSpacing: 1.0,
                          color: textColor,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileTabPills extends ConsumerWidget {
  const _ProfileTabPills({required this.targetUid});

  final String targetUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(_profileTabProvider(targetUid));
    return Row(
      children: [
        Expanded(
          child: _ProfilePill(
            label: 'RUTINAS PÚBLICAS',
            isActive: tab == _ProfileTab.rutinas,
            onTap: () => ref
                .read(_profileTabProvider(targetUid).notifier)
                .state = _ProfileTab.rutinas,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ProfilePill(
            label: 'ACTIVIDAD',
            isActive: tab == _ProfileTab.actividad,
            onTap: () => ref
                .read(_profileTabProvider(targetUid).notifier)
                .state = _ProfileTab.actividad,
          ),
        ),
      ],
    );
  }
}

class _ProfilePill extends StatelessWidget {
  const _ProfilePill({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? palette.accent : palette.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? palette.accent : palette.border,
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.0,
              color: isActive ? palette.bg : palette.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileTabBody extends ConsumerWidget {
  const _ProfileTabBody({required this.targetUid});

  final String targetUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(_profileTabProvider(targetUid));
    return switch (tab) {
      _ProfileTab.rutinas => _RutinasTabBody(targetUid: targetUid),
      _ProfileTab.actividad => _ActividadTabBody(targetUid: targetUid),
    };
  }
}

class _RutinasTabBody extends ConsumerWidget {
  const _RutinasTabBody({required this.targetUid});

  final String targetUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final routines = ref.watch(publicRoutinesByUserProvider(targetUid));

    if (routines.isEmpty) {
      return _EmptyState(
        palette: palette,
        text: 'Aún no hay rutinas públicas.', // i18n: Fase W2
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final routine in routines)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: RoutineCard(routine: routine),
            ),
        ],
      ),
    );
  }
}

class _ActividadTabBody extends ConsumerWidget {
  const _ActividadTabBody({required this.targetUid});

  final String targetUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final postsAsync = ref.watch(visiblePostsByAuthorProvider(targetUid));

    return postsAsync.when(
      data: (posts) {
        if (posts.isEmpty) {
          return _EmptyState(
            palette: palette,
            text: 'Aún no hay actividad reciente.', // i18n: Fase W2
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final post in posts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: PostCard(post: post),
                ),
            ],
          ),
        );
      },
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: CircularProgressIndicator(color: palette.accent),
        ),
      ),
      error: (_, __) => _EmptyState(
        palette: palette,
        text: 'No pudimos cargar la actividad.', // i18n: Fase W2
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.palette, required this.text});

  final AppPalette palette;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(
          text,
          style: GoogleFonts.barlow(
            fontSize: 14,
            color: palette.textMuted,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
