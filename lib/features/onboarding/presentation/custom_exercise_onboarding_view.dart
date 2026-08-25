import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/motion/treino_tappable.dart';
import 'onboarding_card_content.dart';
import '../../../app/theme/tokens/primitives.dart';

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
            const _Grabber(),
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
            _Dots(
              current: _index,
              total: total,
              semanticsLabel: widget.stepSemanticsLabel(_index + 1, total),
            ),
            const SizedBox(height: 14),
            _Actions(
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
            _Dots(
              current: _index,
              total: total,
              semanticsLabel: widget.stepSemanticsLabel(_index + 1, total),
            ),
            const Spacer(),
            _Actions(
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
          _Kicker(step),
          const SizedBox(height: 8),
          _Title(content.title),
          const SizedBox(height: 8),
          _Body(content.body),
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
                _Kicker(step),
                const SizedBox(height: 8),
                _Title(content.title, size: 32),
                const SizedBox(height: 12),
                _Body(content.body, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────── bits

/// "PASO 1 DE 3" over the headline.
class _Kicker extends StatelessWidget {
  const _Kicker(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Text(
      text.toUpperCase(),
      style: GoogleFonts.barlowCondensed(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.6,
        height: 1.0,
        color: palette.accent,
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text, {this.size = 22});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Text(
      text,
      style: GoogleFonts.barlowCondensed(
        fontSize: size,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        height: 1.05,
        color: palette.textPrimary,
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.text, {this.size = 14});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Text(
      text,
      style: GoogleFonts.barlow(
        fontSize: size,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: palette.textMuted,
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Container(
        width: 40,
        height: AppSpacing.hairline,
        decoration: BoxDecoration(
          color: palette.border,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
      ),
    );
  }
}

/// Progress dots. The active one is a pill, so progress survives greyscale and
/// does not depend on colour alone.
class _Dots extends StatelessWidget {
  const _Dots({
    required this.current,
    required this.total,
    required this.semanticsLabel,
  });

  final int current;
  final int total;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < total; i++)
            AnimatedContainer(
              duration: AppMotion.resolve(context, AppMotion.fast),
              curve: AppMotion.standard,
              margin: EdgeInsets.only(right: i == total - 1 ? 0 : 8),
              width: i == current ? 22 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == current
                    ? palette.accent
                    : palette.textPrimary.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.showSkip,
    required this.skipLabel,
    required this.primaryLabel,
    required this.onSkip,
    required this.onPrimary,
    required this.ctaHeight,
    this.expandCta = true,
  });

  final bool showSkip;
  final String skipLabel;
  final String primaryLabel;
  final VoidCallback onSkip;
  final VoidCallback onPrimary;
  final double ctaHeight;
  final bool expandCta;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final cta = _PrimaryCta(
      label: primaryLabel,
      onPressed: onPrimary,
      height: ctaHeight,
    );

    return Row(
      mainAxisSize: expandCta ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (showSkip) ...[
          TextButton(
            key: const Key('custom_exercise_onboarding_skip_button'),
            onPressed: onSkip,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              // 44pt minimum touch target (a11y, #619).
              minimumSize: const Size(44, 44),
              foregroundColor: palette.textMuted,
            ),
            child: Text(
              skipLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.barlowCondensed(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: palette.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        if (expandCta) Expanded(child: cta) else cta,
      ],
    );
  }
}

/// Pill CTA.
///
/// `TreinoTappable` + `Container` rather than `ElevatedButton`, the
/// post-Motion-PR3 construction `HomeCTAButton` documents. `TreinoTappable`
/// contributes no semantics of its own, so the `Semantics(button: true)` around
/// it is required, not decoration.
class _PrimaryCta extends StatelessWidget {
  const _PrimaryCta({
    required this.label,
    required this.onPressed,
    required this.height,
  });

  final String label;
  final VoidCallback onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Semantics(
      button: true,
      label: label,
      child: TreinoTappable(
        key: const Key('custom_exercise_onboarding_primary_cta'),
        onTap: onPressed,
        child: Container(
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: palette.accent,
            borderRadius: BorderRadius.circular(AppRadius.full),
            boxShadow: [
              BoxShadow(
                color: palette.accent.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.barlowCondensed(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              // Ink on accent, never `palette.bg` — see the `_onAccent` note in
              // custom_exercise_onboarding_art.dart for the contrast numbers.
              color: AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}
