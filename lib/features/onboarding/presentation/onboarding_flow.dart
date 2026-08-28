import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';
import 'onboarding_slide.dart';
import 'widgets/onboarding_device_preview.dart';
import '../../../app/theme/tokens/primitives.dart';

/// The welcome tour shell: five slides, each pairing a shrunk-down view of an
/// app screen with a headline, a line of copy, and a CTA.
///
/// Role-agnostic on purpose. The athlete and the trainer get the same shell —
/// same progress bar, same SKIP, same mini-device, same CTA — and differ only
/// in the [slides] they are handed. Duplicating this per role is how the two
/// tours would drift apart one small fix at a time.
///
/// Shell structure mirrors `ProfileSetupFlow` — fixed header, `Expanded`
/// PageView body, fixed footer — because it is the same kind of surface and
/// the two should not drift apart. The deliberate difference is that this one
/// swipes: ProfileSetupFlow gates progression on a form and therefore uses
/// `NeverScrollableScrollPhysics`, while a tour nobody can swipe is a slideshow.
///
/// Purely presentational: it takes its slides and hands back two callbacks.
/// That is what lets it be tested with a bare wrapper and no overrides.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({
    super.key,
    required this.slides,
    required this.onFinish,
    required this.onSkip,
    required this.skipLabel,
    required this.nextLabel,
    required this.finishLabel,
    required this.lastStepLabel,
    required this.stepSemanticsLabel,
  });

  final List<OnboardingSlide> slides;

  /// Last slide's CTA. The caller persists the flag and leaves.
  final VoidCallback onFinish;

  /// SKIP — available from the very first slide. Same contract as [onFinish]:
  /// a tour you cannot leave is a toll, not a welcome.
  final VoidCallback onSkip;

  final String skipLabel;
  final String nextLabel;
  final String finishLabel;

  /// Sits where SKIP sat, on the last slide.
  ///
  /// SKIP has nothing left to skip there, but simply hiding it left a visible
  /// hole beside the full progress bar. A short "you made it" label fills the
  /// slot without adding a second control that does the same thing as the CTA.
  final String lastStepLabel;

  /// Screen-reader label for the progress bar, already interpolated
  /// (e.g. "Paso 2 de 5"). The segments themselves are decorative.
  final String Function(int current, int total) stepSemanticsLabel;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
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
    _controller.nextPage(
      duration: AppMotion.resolve(context, AppMotion.slow),
      curve: AppMotion.standard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final total = widget.slides.length;

    return Scaffold(
      backgroundColor: palette.bg,
      body: MediaQuery(
        // Clamp OS text scaling: header and footer are fixed while the body is
        // Expanded, so an extreme accessibility setting would push the PageView
        // off-screen. Same guard as ProfileSetupFlow (audit F4).
        data: MediaQuery.of(context).copyWith(
          textScaler: MediaQuery.textScalerOf(context)
              .clamp(minScaleFactor: 1.0, maxScaleFactor: 1.3),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s20, AppSpacing.s14, AppSpacing.s20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        label: widget.stepSemanticsLabel(_index + 1, total),
                        excludeSemantics: true,
                        child: _ProgressBar(current: _index, total: total),
                      ),
                    ),
                    const SizedBox(width: 18),
                    // SKIP has nothing left to skip on the last slide, and the
                    // CTA already reads EMPEZAR — so the slot swaps to a plain
                    // label rather than emptying out.
                    if (_isLast)
                      _SlotLabel(text: widget.lastStepLabel)
                    else
                      _SkipButton(
                        label: widget.skipLabel,
                        onPressed: widget.onSkip,
                      ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  key: const Key('onboarding_page_view'),
                  controller: _controller,
                  itemCount: total,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) =>
                      _SlideView(slide: widget.slides[i]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.s20,
                    AppSpacing.s20, AppSpacing.s20, AppSpacing.s20),
                child: Column(
                  children: [
                    // No drawn home-indicator bar: the handoff removed it so the
                    // device's own system gesture bar is the only one on screen.
                    _PrimaryCta(
                      label: _isLast ? widget.finishLabel : widget.nextLabel,
                      onPressed: _onPrimary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One slide: device preview on top, headline and copy below.
class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});

  final OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    0, AppSpacing.s18, 0, AppSpacing.s8),
                child: OnboardingDevicePreview(child: slide.preview),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 4,
                          height: 38,
                          decoration: BoxDecoration(
                            color: palette.accent,
                            borderRadius: BorderRadius.circular(
                                AppDecorativeRadii.progressSegment),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Icon(slide.icon, size: 28, color: palette.accent),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            slide.title,
                            style: GoogleFonts.barlowCondensed(
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              height: 1.0,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      slide.body,
                      style: GoogleFonts.barlow(
                        fontSize: 17,
                        fontWeight: FontWeight.w400,
                        height: 1.5,
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Five segments, filled left-to-right up to the current slide.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Row(
      children: List.generate(total, (i) {
        return Expanded(
          child: AnimatedContainer(
            duration: AppMotion.resolve(context, AppMotion.fast),
            curve: AppMotion.standard,
            margin: EdgeInsets.only(right: i == total - 1 ? 0 : AppSpacing.s12),
            height: 4,
            decoration: BoxDecoration(
              color: i <= current ? palette.accent : palette.border,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
          ),
        );
      }),
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return TextButton(
      key: const Key('onboarding_skip_button'),
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        // 44pt minimum touch target (a11y, #619).
        minimumSize: const Size(44, 44),
        tapTargetSize: MaterialTapTargetSize.padded,
        foregroundColor: palette.textMuted,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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

/// Non-interactive text in the SKIP slot. Same typography as [_SkipButton] so
/// the header keeps its rhythm, minus the button affordance — there is nothing
/// to press here.
class _SlotLabel extends StatelessWidget {
  const _SlotLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.barlowCondensed(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
          color: palette.accent,
        ),
      ),
    );
  }
}

class _PrimaryCta extends StatelessWidget {
  const _PrimaryCta({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.full),
        boxShadow: [
          BoxShadow(
            color: palette.accent.withValues(alpha: 0.42),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ElevatedButton(
        key: const Key('onboarding_primary_cta'),
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.accent,
          // Ink on accent, per AppTheme's `onPrimary: palette.bg`. In dark mode
          // that is near-black on green — NOT white. Getting this wrong is the
          // single most visible theme bug on this screen.
          foregroundColor: palette.bg,
          shape: const StadiumBorder(),
          padding: EdgeInsets.zero,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.barlowCondensed(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            color: palette.bg,
          ),
        ),
      ),
    );
  }
}
