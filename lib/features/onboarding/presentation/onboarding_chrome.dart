/// The chrome every onboarding sheet and dialog draws around its content:
/// grabber, kicker, title, body, dots, SALTAR + CTA pill.
///
/// Extracted from `custom_exercise_onboarding_view.dart` when the PLANTILLAS
/// mini-onboarding (#635) arrived with the same anatomy but interactive
/// content. The two are NOT the same view — one pages through passive slides,
/// the other collects four answers — but the frame around them is drawn from
/// one handoff, so a copy would drift the moment either side is retouched.
///
/// Every widget here is purely presentational: no Riverpod, no navigation, no
/// persistence. Keys are passed in rather than hardcoded so each surface keeps
/// the finder names its own tests already use.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/motion/treino_tappable.dart';

/// "PASO 1 DE 4" over the headline. Barlow Condensed 700, accent, tracked out.
class OnboardingKicker extends StatelessWidget {
  const OnboardingKicker(this.text, {super.key});

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

/// Slide headline. Barlow Condensed 700 — the handoff sets it UPPERCASE in the
/// copy itself rather than here, so a title that needs sentence case can have
/// one without a flag.
class OnboardingTitle extends StatelessWidget {
  const OnboardingTitle(this.text, {super.key, this.size = 22});

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

/// Supporting sentence under the headline. Barlow 400, muted.
class OnboardingBody extends StatelessWidget {
  const OnboardingBody(this.text, {super.key, this.size = 14});

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

/// The drag handle at the top of a bottom sheet.
class OnboardingGrabber extends StatelessWidget {
  const OnboardingGrabber({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: palette.border,
          borderRadius: BorderRadius.circular(9999),
        ),
      ),
    );
  }
}

/// Progress dots. The active one is a pill, so progress survives greyscale and
/// does not depend on colour alone.
class OnboardingDots extends StatelessWidget {
  const OnboardingDots({
    super.key,
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
                borderRadius: BorderRadius.circular(9999),
              ),
            ),
        ],
      ),
    );
  }
}

/// SALTAR + the primary pill, as one row.
class OnboardingActions extends StatelessWidget {
  const OnboardingActions({
    super.key,
    required this.showSkip,
    required this.skipLabel,
    required this.primaryLabel,
    required this.onSkip,
    required this.onPrimary,
    required this.ctaHeight,
    this.expandCta = true,
    this.skipKey,
    this.primaryKey,
  });

  final bool showSkip;
  final String skipLabel;
  final String primaryLabel;
  final VoidCallback onSkip;
  final VoidCallback onPrimary;
  final double ctaHeight;
  final bool expandCta;

  /// Finder keys, supplied by the surface rather than fixed here: each
  /// onboarding keeps the names its own tests already assert on.
  final Key? skipKey;
  final Key? primaryKey;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final cta = OnboardingPrimaryCta(
      key: primaryKey,
      label: primaryLabel,
      onPressed: onPrimary,
      height: ctaHeight,
    );

    return Row(
      mainAxisSize: expandCta ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (showSkip) ...[
          TextButton(
            key: skipKey,
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
class OnboardingPrimaryCta extends StatelessWidget {
  const OnboardingPrimaryCta({
    super.key,
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
        onTap: onPressed,
        child: Container(
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: palette.accent,
            borderRadius: BorderRadius.circular(9999),
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
