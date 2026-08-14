import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/primitives.dart';
import '../onboarding_sample_data.dart';

/// A real app screen, shrunk into a floating mini-device.
///
/// The child is laid out at [kScreenWidth] — the logical width of the phone the
/// design was drawn against — and then scaled by [kScale]. That order matters:
/// laying out at the real width and scaling the result is what makes the
/// preview a faithful miniature of the shipped screen. Handing the real widgets
/// a 220pt-wide constraint instead would re-flow every text wrap and column
/// break, and the preview would quietly stop matching the app.
///
/// The child runs inside a nested [ProviderScope] seeded with
/// [onboardingSampleOverrides], so the previews render representative data and
/// never touch the signed-in account. See `onboarding_sample_data.dart` for why
/// that override list must stay exhaustive.
class OnboardingDevicePreview extends StatelessWidget {
  const OnboardingDevicePreview({super.key, required this.child});

  /// The screen to miniaturise, built as if it had the full phone width.
  final Widget child;

  /// iPhone 14/15 logical width — what the handoff mock was drawn at.
  static const double kScreenWidth = 393;

  static const double kScale = 0.56;

  /// Visible size of the screen inside the bezel.
  static const Size kScreenSize = Size(220, 456);

  /// The screen's height expressed in CONTENT coordinates — i.e. before
  /// [kScale] shrinks it. This is the height the previewed screen is laid
  /// out against, and it must stay finite: the real screens build ListViews,
  /// and a viewport handed an unbounded height cannot lay out at all.
  static const double kContentHeight = 456 / kScale;

  /// How tall the previewed screen is allowed to lay itself out before the
  /// frame clips it.
  ///
  /// Generously larger than [kContentHeight] because these are real screens:
  /// they are written to fill a phone and keep scrolling, so pinning them to
  /// exactly the visible height paints an overflow stripe across the mock. It
  /// must still be FINITE — the screens build ListViews, and a viewport handed
  /// an unbounded height refuses to lay out at all.
  static const double kContentMaxHeight = kContentHeight * 2;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Center(
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          // Deliberately NOT an AppPalette colour: the bezel is the phone's
          // physical chassis, not app UI, so it stays white in both themes.
          // The handoff calls this out explicitly. Its shadow follows the same
          // rule and lives in AppDecorativePalettes for the same reason —
          // decorative and theme-invariant, not a semantic token.
          color: Colors.white,
          borderRadius: BorderRadius.circular(34),
          boxShadow: [
            BoxShadow(
              color: AppDecorativePalettes.deviceFrameShadow
                  .withValues(alpha: 0.14),
              blurRadius: 44,
              offset: const Offset(0, 22),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 0,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: SizedBox(
                width: kScreenSize.width,
                height: kScreenSize.height,
                child: ColoredBox(
                  color: palette.bg,
                  child: Stack(
                    children: [
                      // The two AppBackground glows, at the same corners and
                      // opacities the real screen uses.
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: const Alignment(-0.7, -0.76),
                              radius: 0.7,
                              colors: [
                                palette.accent.withValues(alpha: 0.20),
                                palette.accent.withValues(alpha: 0),
                              ],
                              stops: const [0, 0.85],
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: const Alignment(0.8, 0.9),
                              radius: 0.7,
                              colors: [
                                palette.highlight.withValues(alpha: 0.14),
                                palette.highlight.withValues(alpha: 0),
                              ],
                              stops: const [0, 0.85],
                            ),
                          ),
                        ),
                      ),
                      // Lay out at full phone width, then scale down. OverflowBox
                      // forces the wide constraint through the 220pt-wide parent;
                      // the ClipRRect above trims whatever falls past the screen.
                      OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: kScreenWidth,
                        maxWidth: kScreenWidth,
                        minHeight: kContentHeight,
                        maxHeight: kContentHeight,
                        child: Transform.scale(
                          scale: kScale,
                          alignment: Alignment.topLeft,
                          child: MediaQuery(
                            // Pin the text scale. The preview is a picture of the
                            // app, not a surface the user reads: letting the OS
                            // setting through would re-wrap the miniature while
                            // the surrounding copy already scales on its own.
                            data: MediaQuery.of(context).copyWith(
                              textScaler: TextScaler.noScaling,
                              padding: EdgeInsets.zero,
                              viewPadding: EdgeInsets.zero,
                              viewInsets: EdgeInsets.zero,
                            ),
                            child: ExcludeSemantics(
                              child: ProviderScope(
                                overrides: onboardingSampleOverrides(),
                                child: child,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Earpiece slot. Sits on the white chassis, so it is chassis-tinted
            // rather than palette-tinted, same reasoning as the bezel.
            Positioned(
              top: -5,
              child: Container(
                width: 52,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
