/// The five screens the tour previews.
///
/// Each one composes the SAME widgets its real screen composes, in the same
/// order and with the same spacing — that is the whole point of the approach.
/// A hand-drawn mock-up would go stale silently; if one of these stops matching
/// the app, it is because a widget's constructor changed, and the build breaks.
///
/// Two deliberate departures, both forced:
///  * The screens' own roots are private (`_AthleteHome`, `_AthleteFeed`, …),
///    so the composition is repeated here rather than reused.
///  * The tab bars are rendered as static pills. A real `TabBar` needs a
///    controller and a live `TabBarView`, which a still frame has no use for.
///
/// Everything renders inside `OnboardingDevicePreview`, which supplies the
/// sample-data `ProviderScope`.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../coach/athlete_coach_view.dart';
import '../../feed/presentation/widgets/feed_segment_pills.dart';
import '../../feed/presentation/widgets/post_card.dart';
import '../../home/widgets/empezar_entrenamiento_card.dart';
import '../../home/widgets/esta_semana_card.dart';
import '../../home/widgets/home_header.dart';
import '../../profile/presentation/widgets/profile_avatar_card.dart';
import '../../profile/presentation/widgets/profile_section_tile.dart';
import '../../workout/presentation/widgets/historial_section.dart';
import '../../workout/presentation/widgets/rutinas_section.dart';
import 'onboarding_sample_data.dart';
import 'widgets/onboarding_device_preview.dart';
import 'widgets/onboarding_nav_bar.dart';
import 'widgets/onboarding_preview_cards.dart';
import '../../../app/theme/tokens/primitives.dart';

// ── 1 — Resumen del día ─────────────────────────────────────────────────────

/// Mirrors `_AthleteHome`: header, today's routine card, this-week card.
class OnboardingHomePreview extends StatelessWidget {
  const OnboardingHomePreview({super.key});

  @override
  Widget build(BuildContext context) {
    return _PreviewShell(
      activeTab: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            HomeHeader(profile: sampleProfile),
            const SizedBox(height: 20),
            const EmpezarEntrenamientoCard(),
            const SizedBox(height: 12),
            const EstaSemanaCard(),
          ],
        ),
      ),
    );
  }
}

// ── 2 — Entrenar ────────────────────────────────────────────────────────────

/// Mirrors the athlete workout tab: `[TU ENTRENO | PLANTILLAS]`, then routines
/// and history.
class OnboardingWorkoutPreview extends StatelessWidget {
  const OnboardingWorkoutPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PreviewShell(
      activeTab: 0,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 20),
            _SegmentedPill(labels: ['TU ENTRENO', 'PLANTILLAS']),
            SizedBox(height: 20),
            RutinasSection(),
            SizedBox(height: 20),
            HistorialSection(),
            SizedBox(height: 20),
            OnboardingVolumeCard(),
          ],
        ),
      ),
    );
  }
}

// ── 3 — Feed ────────────────────────────────────────────────────────────────

/// Mirrors `_AthleteFeed`: the `[FEED | RANKINGS]` tab bar, the audience pills,
/// and a post.
class OnboardingFeedPreview extends StatelessWidget {
  const OnboardingFeedPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return _PreviewShell(
      activeTab: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: _SegmentedPill(labels: ['FEED', 'RANKINGS']),
          ),
          const SizedBox(height: 16),
          const FeedSegmentPills(),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                PostCard(post: samplePostTwo),
                const SizedBox(height: 14),
                PostCard(post: samplePost),
                const SizedBox(height: 14),
                // Drawn rather than delegated to PostCard: the real card loads
                // photoUrl over the network and collapses the image when the
                // URL is unreachable, so a bundled asset produced a photo post
                // with no photo. See OnboardingPhotoPost.
                const OnboardingPhotoPost(
                  author: 'Martín Aguirre',
                  meta: 'Gimnasio Central · hace 8 h',
                  text: 'Legs day. Foto obligatoria antes de que me fallen '
                      'las piernas.',
                  reactions: [
                    (icon: TreinoIcon.reactionLike, count: 12),
                    (icon: TreinoIcon.reactionFire, count: 6),
                    (icon: TreinoIcon.reactionClap, count: 3),
                  ],
                ),
                const OnboardingInlineComment(
                  author: 'Sofi',
                  text: 'Esas piernas van a hablar mañana 😅',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 4 — Coach ───────────────────────────────────────────────────────────────

/// The active-link card, on its own.
///
/// `AthleteCoachView` is deliberately NOT mounted here: it fires
/// `_maybeShow30DayPrompt()` from a post-frame callback, which would open a
/// modal sheet on top of the tour. [LinkStateCard] is the part the slide is
/// about, and it was made public for exactly this.
class OnboardingCoachPreview extends StatelessWidget {
  const OnboardingCoachPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return _PreviewShell(
      activeTab: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            // LinkStateCard builds a ListView (athlete_coach_view.dart:201).
            // On the real COACH tab that list sits in a bounded tab body; in a
            // Column it would be handed unbounded height and refuse to lay out,
            // which is precisely why this slide rendered EMPTY on device. The
            // explicit height is the bounded parent it expects — sized to the
            // card's own content so the slide does not open a dead gap above
            // PLAN ASIGNADO.
            SizedBox(
              height: 392,
              child: LinkStateCard(link: sampleTrainerLink),
            ),
            const SizedBox(height: 16),
            const OnboardingAssignedPlanCard(),
            const SizedBox(height: 16),
            const OnboardingLastMessageCard(),
          ],
        ),
      ),
    );
  }
}

// ── 5 — Perfil ──────────────────────────────────────────────────────────────

/// Mirrors `_AthleteProfile`: the avatar card and the CUENTA group.
class OnboardingProfilePreview extends StatelessWidget {
  const OnboardingProfilePreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PreviewShell(
      activeTab: 4,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 20),
            _SegmentedPill(labels: ['TU CUENTA', 'PERFIL']),
            SizedBox(height: 20),
            ProfileAvatarCard(),
            SizedBox(height: 14),
            OnboardingProfileStats(),
            SizedBox(height: 20),
            _GroupLabel('CUENTA'),
            SizedBox(height: 12),
            ProfileSectionTile(
              icon: Icons.person_outline,
              title: 'Datos personales',
              onTap: _ignoreProfileTap,
            ),
            SizedBox(height: 10),
            ProfileSectionTile(
              icon: Icons.fitness_center_outlined,
              title: 'Gimnasio',
              onTap: _ignoreProfileTap,
            ),
            SizedBox(height: 10),
            ProfileSectionTile(
              icon: Icons.notifications_outlined,
              title: 'Notificaciones',
              onTap: _ignoreProfileTap,
            ),
            SizedBox(height: 10),
            ProfileSectionTile(
              icon: Icons.dark_mode_outlined,
              title: 'Apariencia',
              onTap: _ignoreProfileTap,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared bits ─────────────────────────────────────────────────────────────

/// Screen body plus the real bottom bar, pinned to the bottom of the frame.
class _PreviewShell extends StatelessWidget {
  const _PreviewShell({required this.activeTab, required this.child});

  final int activeTab;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Expanded gives the body a BOUNDED height, and that is load-bearing.
        // These screens contain viewports (RutinasSection, HistorialSection and
        // the link card all build lists), and a viewport under an unbounded
        // main-axis constraint cannot lay out at all: it throws
        // "RenderBox was not laid out" plus `child!.hasSize is not true` from
        // OverflowBox, the whole subtree fails to paint — the preview renders
        // EMPTY — and because it re-throws every frame the tour locks up.
        //
        // The non-scrolling scroll view is what absorbs content taller than the
        // frame without an overflow stripe. It is safe here only because
        // OnboardingDevicePreview wraps this in ExcludeSemantics: a viewport
        // inside the frame's forced constraints otherwise trips Flutter's
        // semantics walk (`RenderViewportBase.visitChildrenForSemantics`).
        // Two constraints have to hold at once here, and they pull opposite ways.
        //
        // The previewed screens build ListViews (RutinasSection,
        // HistorialSection, the trainer-link card). A viewport handed an
        // UNBOUNDED height cannot lay out: it throws "Vertical viewport was
        // given unbounded height", then "RenderBox was not laid out", the whole
        // subtree fails to paint — the preview comes out EMPTY — and the
        // per-frame re-throw locks the tour up. That rules out both
        // `maxHeight: double.infinity` and nesting this in a scroll view.
        //
        // But the content is also taller than the frame by design, so a plain
        // tight box would paint an overflow stripe across the mock.
        //
        // A FINITE OverflowBox satisfies both: nested viewports get a real
        // number to lay out against, and anything past the frame is absorbed
        // and then clipped, which is exactly what a still frame wants.
        Expanded(
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: 0,
              maxHeight: OnboardingDevicePreview.kContentMaxHeight,
              child: child,
            ),
          ),
        ),
        OnboardingNavBar(activeIndex: activeTab),
      ],
    );
  }
}

void _ignoreProfileTap() {}

/// A still rendering of the segmented tab bars the real screens drive with a
/// `TabController`. First label is always the active one.
class _SegmentedPill extends StatelessWidget {
  const _SegmentedPill({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: i == 0 ? palette.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Center(
                  child: Text(
                    labels[i],
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      // Ink on accent — `onPrimary: palette.bg`, dark in dark
                      // mode, not white.
                      color: i == 0 ? palette.bg : palette.textMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: GoogleFonts.barlowCondensed(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
          color: palette.textMuted,
        ),
      ),
    );
  }
}
