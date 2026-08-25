import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';
import 'onboarding_card_content.dart';
import '../../../app/theme/tokens/primitives.dart';

/// Full-screen, swipeable welcome tour: one slide per section, run once right
/// after login.
///
/// Purely presentational: no Riverpod, no repository, no navigation. It takes
/// its slides and hands back two callbacks. That is what lets it be tested with
/// a bare `TestAppWrapper` and no provider overrides.
///
/// Visual language is derived from two already-approved screens rather than
/// invented — there is no onboarding mockup in `docs/design-decisions.md`. The
/// shell (background, safe area, header/body/footer) mirrors `ProfileSetupFlow`;
/// the slide composition (accent-barred headline over muted body) mirrors
/// `WelcomeScreen`.
class OnboardingTourView extends StatefulWidget {
  const OnboardingTourView({
    super.key,
    required this.slides,
    required this.onFinish,
    required this.onSkip,
    required this.skipLabel,
    required this.nextLabel,
    required this.finishLabel,
    required this.stepSemanticsLabel,
  });

  final List<OnboardingCardContent> slides;

  /// Last slide's CTA ("COMENZAR"). The caller persists the flag and closes.
  final VoidCallback onFinish;

  /// SKIP, available from the very first slide. Same contract as [onFinish] —
  /// a tour nobody can leave is a toll, not a welcome.
  final VoidCallback onSkip;

  final String skipLabel;
  final String nextLabel;
  final String finishLabel;

  /// Screen-reader label for the progress indicator, already interpolated
  /// (e.g. "Paso 2 de 5"). The bars themselves are decorative.
  final String Function(int current, int total) stepSemanticsLabel;

  @override
  State<OnboardingTourView> createState() => _OnboardingTourViewState();
}

class _OnboardingTourViewState extends State<OnboardingTourView> {
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
          textScaler: MediaQuery.textScalerOf(context).clamp(
            minScaleFactor: 1.0,
            maxScaleFactor: 1.3,
          ),
        ),
        child: AppBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          label: widget.stepSemanticsLabel(_index + 1, total),
                          excludeSemantics: true,
                          child: _TourProgressBars(
                            current: _index,
                            total: total,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Visible from slide 1 — never hidden behind a scroll and
                      // never deferred to the end.
                      TextButton(
                        key: const Key('onboarding_skip_button'),
                        onPressed: widget.onSkip,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          // 44pt minimum touch target (a11y, #619).
                          minimumSize: const Size(44, 44),
                          foregroundColor: palette.textMuted,
                        ),
                        child: Text(
                          widget.skipLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.4,
                            color: palette.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: PageView.builder(
                      key: const Key('onboarding_page_view'),
                      controller: _controller,
                      // Real swipe — the deliberate difference against
                      // ProfileSetupFlow, which gates progression on a form and
                      // therefore uses NeverScrollableScrollPhysics.
                      itemCount: total,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (context, i) =>
                          _Slide(content: widget.slides[i]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PrimaryCta(
                    label: _isLast ? widget.finishLabel : widget.nextLabel,
                    onPressed: _onPrimary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Segmented progress bar, parameterised by [total].
///
/// Not a reuse of `ProfileSetupHeader`: that widget hardcodes `_totalSteps = 4`
/// and parameterising it would mean editing `profile_setup`, which this change
/// deliberately leaves untouched. Same visual idiom, ~20 lines.
class _TourProgressBars extends StatelessWidget {
  const _TourProgressBars({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Row(
      children: List.generate(total, (i) {
        final filled = i <= current;
        return Expanded(
          child: AnimatedContainer(
            duration: AppMotion.resolve(context, AppMotion.fast),
            curve: AppMotion.standard,
            margin: EdgeInsets.only(right: i == total - 1 ? 0 : AppSpacing.s8),
            height: 4,
            decoration: BoxDecoration(
              color: filled ? palette.accent : palette.border,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
          ),
        );
      }),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.content});

  final OnboardingCardContent content;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // Centered in the space the PageView actually gives us, scrollable when the
    // copy does not fit — a long slide at 1.3x on a 320x568 screen must scroll,
    // never overflow. minHeight comes from the real constraints, not a fraction
    // of the screen: the header and footer live outside this box.
    return LayoutBuilder(
      builder: (context, constraints) {
        // The illustration yields space to the copy as text grows: at 1.3x the
        // words are what the user came for, the drawing is context. Without the
        // divisor a large accessibility setting pushes the headline off-screen
        // behind a scroll on every single slide.
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        // 0.54 rather than something smaller: the copy on these slides is
        // short, so a timid illustration leaves a band of dead space above and
        // below on a tall phone. The ceiling keeps it from dominating on an
        // iPad-sized viewport.
        final artHeight =
            (constraints.maxHeight * 0.54 / textScale).clamp(130.0, 400.0);

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Decorative: it repeats what the headline and body already
                // say, so a screen reader announcing it would only add noise.
                ExcludeSemantics(
                  child: SizedBox(
                    height: artHeight,
                    width: double.infinity,
                    child: content.illustration,
                  ),
                ),
                const SizedBox(height: AppSpacing.s20),
                // Left accent bar over the headline — the WelcomeScreen
                // signature. A left Border spans the child's height on its own,
                // so no IntrinsicHeight is needed.
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(width: 3, color: palette.accent),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(content.icon, size: 24, color: palette.accent),
                        const SizedBox(width: AppSpacing.s12),
                        Expanded(
                          child: Text(
                            content.title,
                            style: GoogleFonts.barlowCondensed(
                              color: palette.textPrimary,
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  content.body,
                  style: GoogleFonts.barlow(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: palette.textMuted,
                    height: 1.5,
                  ),
                ),
                if (content.bullets.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  for (final bullet in content.bullets) ...[
                    _Bullet(text: bullet),
                    const SizedBox(height: 12),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One accent-dotted specific. The dot mirrors the eyebrow marker on
/// `WelcomeScreen`; nudged down so it optically aligns with the first line's cap
/// height rather than its box top.
class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s8),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: palette.accent,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.barlow(
              color: palette.textPrimary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// Pill CTA.
///
/// Not `AuthPillButton`: that widget lives in `features/auth` and importing it
/// would couple onboarding to auth for 20 lines. Same tokens, same shape —
/// r-full, accent, 56 high, accent@18% halo.
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
            color: palette.accent.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        key: const Key('onboarding_primary_cta'),
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.accent,
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
            letterSpacing: 1.0,
            color: palette.bg,
          ),
        ),
      ),
    );
  }
}
