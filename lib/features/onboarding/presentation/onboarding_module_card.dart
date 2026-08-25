import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import 'onboarding_card_content.dart';
import '../../../app/theme/tokens/primitives.dart';

/// The card a module shows the first time the user opens it.
///
/// Purely presentational: no Riverpod, no repository, no persistence. It takes
/// its copy and hands back one callback. That is what lets it be tested with a
/// bare `TestAppWrapper` and no provider overrides, and re-skinned later without
/// any other unit noticing.
///
/// Rendered CENTERED, as a dialog over the screen it explains. It was inline at
/// the top first; centering it won on two counts: it reads as an explainer
/// ABOUT the screen rather than as content ON it, and it stops shifting the
/// layout underneath — the inline version pushed real content down and broke
/// assertions in screens that had nothing to do with onboarding.
///
/// Visual language is the card formula already repeated across the repo
/// (`bgCard` + 1px `border` + r-20 for dialogs), not something invented here.
class OnboardingModuleCard extends StatelessWidget {
  const OnboardingModuleCard({
    super.key,
    required this.content,
    required this.dismissLabel,
    required this.onDismiss,
  });

  final OnboardingCardContent content;

  /// "ENTENDIDO". The single way out — no second X in the corner, so there is
  /// one path to test and one path to get wrong.
  final String dismissLabel;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        // Fixed max width, no breakpoints — the idiom every dialog in this repo
        // already uses. SingleChildScrollView absorbs short viewports and large
        // text scales instead of overflowing.
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: palette.bgCard,
              border: Border.all(color: palette.border),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(content.icon, size: 20, color: palette.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        content.title,
                        style: GoogleFonts.barlowCondensed(
                          color: palette.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  content.body,
                  style: GoogleFonts.barlow(
                    color: palette.textMuted,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                if (content.bullets.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  for (final bullet in content.bullets) ...[
                    _Bullet(text: bullet),
                    const SizedBox(height: 8),
                  ],
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('onboarding_card_dismiss'),
                    onPressed: onDismiss,
                    style: TextButton.styleFrom(
                      // 44pt minimum touch target (a11y, #619).
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      foregroundColor: palette.accent,
                    ),
                    // Label only — no trailing icon. At large text scales a
                    // Row[text, icon] on a 320pt screen overflows horizontally, and
                    // the icon says nothing the word does not already say.
                    child: Text(
                      dismissLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.barlowCondensed(
                        color: palette.accent,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: palette.accent,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.barlow(
              color: palette.textPrimary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
