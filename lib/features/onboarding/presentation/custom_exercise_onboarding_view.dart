import 'package:flutter/material.dart';

import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';
import 'onboarding_card_content.dart';
import 'onboarding_chrome.dart';

// Finder keys. They live here rather than in `OnboardingChrome` because the
// chrome is now shared with the PLANTILLAS onboarding (#635) and each surface
// keeps the names its own tests already assert on.
const _skipKey = Key('custom_exercise_onboarding_skip_button');
const _ctaKey = Key('custom_exercise_onboarding_primary_cta');

/// How the onboarding is being presented.
///
/// The two are not a responsive breakpoint on one layout — they are two
/// presentations the handoff draws separately, and the Coach Hub never renders
/// the sheet: `CoachHubScaffold` replaces the whole shell with `MobileBanner`
/// below 768px, so the dialog is always on a desktop-class viewport.
enum CustomExerciseOnboardingLayout {
  /// Mobile bottom sheet — art on top, copy under it, actions at the bottom.
  sheet,

  /// Coach Hub dialog — art on the left, copy on the right, actions in a
  /// footer under a divider.
  dialog,
}

/// The "Creá tus propios ejercicios" onboarding, as a widget.
///
/// Purely presentational: no Riverpod, no repository, no navigation. It takes
/// its slides and hands back two callbacks — the same contract as
/// [OnboardingTourView], and what lets it be tested with a bare
/// `TestAppWrapper` and no provider overrides.
///
/// Both callbacks are terminal and equivalent to the caller: SALTAR and the
/// final CTA persist the same flag. A tour nobody can leave is a toll, not a
/// welcome (#429).
class CustomExerciseOnboardingView extends StatefulWidget {
  const CustomExerciseOnboardingView({
    super.key,
    required this.slides,
    required this.onFinish,
    required this.onSkip,
    required this.skipLabel,
    required this.nextLabel,
    required this.finishLabel,
    required this.stepSemanticsLabel,
    this.layout = CustomExerciseOnboardingLayout.sheet,
  });

  final List<OnboardingCardContent> slides;

  /// Last slide's CTA. The caller persists the flag and closes.
  final VoidCallback onFinish;

  /// SALTAR — offered on every slide but the last, where the CTA already ends
  /// the flow and a second "leave" control would just be noise.
  final VoidCallback onSkip;

  final String skipLabel;
  final String nextLabel;
  final String finishLabel;

  /// Screen-reader label for the dots, already interpolated ("Paso 2 de 3").
  final String Function(int current, int total) stepSemanticsLabel;

  final CustomExerciseOnboardingLayout layout;

  @override
  State<CustomExerciseOnboardingView> createState() =>
      _CustomExerciseOnboardingViewState();
}

class _CustomExerciseOnboardingViewState
    extends State<CustomExerciseOnboardingView> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _index == widget.slides.length - 1;

  void _onPrimary() {
    if (_isLast) {
      widget.onFinish();
      return;
    }
    // `resolve` is what honours reduce-motion — a raw duration here would
    // animate for a user who asked the OS for no animation.
    _controller.nextPage(
      duration: AppMotion.resolve(context, AppMotion.slow),
      curve: AppMotion.standard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDialog = widget.layout == CustomExerciseOnboardingLayout.dialog;

    return MediaQuery(
      // Clamp OS text scaling: the actions row is fixed while the pager is
      // Expanded, so an extreme accessibility setting would push the CTA off
      // the sheet. Same guard as OnboardingTourView and ProfileSetupFlow.
      data: MediaQuery.of(context).copyWith(
        textScaler: MediaQuery.textScalerOf(context).clamp(
          minScaleFactor: 1.0,
          maxScaleFactor: 1.3,
        ),
      ),
      child: isDialog ? _buildDialog(context) : _buildSheet(context),
    );
  }

  // ─────────────────────────────────────────────────────────────── mobile

  Widget _buildSheet(BuildContext context) {
    final total = widget.slides.length;

    // A `PageView` has no intrinsic height — it expands to fill whatever it is
    // given. Left in a `Flexible` it swallowed the whole 90%-of-screen sheet and
    // left a dead band between the copy and the dots. So the height is computed
    // instead: enough for the tallest slide, and never more than the sheet has.
    return LayoutBuilder(
      builder: (context, constraints) {
        // grabber 22 + gap 14 + dots 6 + gap 14 + actions 52.
        const chrome = 108.0;
        // art 150 + gaps 30 + kicker 12 + title ~48 (it wraps to two lines) +
        // body ~60. Scaled with the text, because the copy is what grows.
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final wanted = 300.0 * textScale;
        final available = constraints.maxHeight - chrome;
        final pagerHeight =
            available > 0 && wanted > available ? available : wanted;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const OnboardingGrabber(),
            SizedBox(
              height: pagerHeight,
              child: PageView.builder(
                key: const Key('custom_exercise_onboarding_page_view'),
                controller: _controller,
                itemCount: total,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _SheetSlide(
                  content: widget.slides[i],
                  step: widget.stepSemanticsLabel(i + 1, total),
                ),
              ),
            ),
            const SizedBox(height: 14),
            OnboardingDots(
              current: _index,
              total: total,
              semanticsLabel: widget.stepSemanticsLabel(_index + 1, total),
            ),
            const SizedBox(height: 14),
            OnboardingActions(
              skipKey: _skipKey,
              primaryKey: _ctaKey,
              showSkip: !_isLast,
              skipLabel: widget.skipLabel,
              primaryLabel: _isLast ? widget.finishLabel : widget.nextLabel,
              onSkip: widget.onSkip,
              onPrimary: _onPrimary,
              ctaHeight: 48,
            ),
          ],
        );
      },
    );
  }

  // ────────────────────────────────────────────────────────────────── web

  Widget _buildDialog(BuildContext context) {
    final palette = AppPalette.of(context);
    final total = widget.slides.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 260,
          child: PageView.builder(
            key: const Key('custom_exercise_onboarding_page_view'),
            controller: _controller,
            itemCount: total,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => _DialogSlide(
              content: widget.slides[i],
              step: widget.stepSemanticsLabel(i + 1, total),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Divider(height: 1, color: palette.border),
        const SizedBox(height: 20),
        Row(
          children: [
            OnboardingDots(
              current: _index,
              total: total,
              semanticsLabel: widget.stepSemanticsLabel(_index + 1, total),
            ),
            const Spacer(),
            OnboardingActions(
              skipKey: _skipKey,
              primaryKey: _ctaKey,
              showSkip: !_isLast,
              skipLabel: widget.skipLabel,
              primaryLabel: _isLast ? widget.finishLabel : widget.nextLabel,
              onSkip: widget.onSkip,
              onPrimary: _onPrimary,
              ctaHeight: 48,
              // In the footer the CTA hugs its label instead of stretching:
              // a full-width pill under a 780pt dialog reads as a page action,
              // not as "next".
              expandCta: false,
            ),
          ],
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────── slides

class _SheetSlide extends StatelessWidget {
  const _SheetSlide({required this.content, required this.step});

  final OnboardingCardContent content;
  final String step;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Decorative: it repeats what the headline and body already say, so a
          // screen reader announcing it would only add noise.
          ExcludeSemantics(
            child: SizedBox(height: 150, child: content.illustration),
          ),
          const SizedBox(height: 14),
          OnboardingKicker(step),
          const SizedBox(height: 8),
          OnboardingTitle(content.title),
          const SizedBox(height: 8),
          OnboardingBody(content.body),
        ],
      ),
    );
  }
}

class _DialogSlide extends StatelessWidget {
  const _DialogSlide({required this.content, required this.step});

  final OnboardingCardContent content;
  final String step;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ExcludeSemantics(
          child: SizedBox(width: 330, child: content.illustration),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                OnboardingKicker(step),
                const SizedBox(height: 8),
                OnboardingTitle(content.title, size: 32),
                const SizedBox(height: 12),
                OnboardingBody(content.body, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
