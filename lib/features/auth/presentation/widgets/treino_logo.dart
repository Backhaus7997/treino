import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../app/theme/app_palette.dart';

/// TREINO brand logo rendered from `assets/logo/treino_logo.svg`.
///
/// The SVG uses `currentColor`, so its tint is controlled by [color] —
/// defaults to `palette.textPrimary`. Aspect ratio ≈ 1.97:1; [size] is
/// the rendered height in logical pixels.
///
/// When [glow] is true (default), an accent halo is painted behind the
/// logo to match the brand mockups. Set false for tight contexts.
class TreinoLogo extends StatelessWidget {
  const TreinoLogo({
    super.key,
    this.size = 56,
    this.color,
    this.glow = true,
  });

  /// Logo height in logical pixels.
  final double size;

  /// Tint color. Defaults to `palette.textPrimary`.
  final Color? color;

  /// Whether to paint an accent halo behind the logo.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final logo = SvgPicture.asset(
      'assets/logo/treino_logo.svg',
      height: size,
      colorFilter: ColorFilter.mode(
        color ?? palette.textPrimary,
        BlendMode.srcIn,
      ),
    );

    if (!glow) return logo;

    // Outer glow — render the SVG twice in accent with progressive blur
    // sigmas, then the sharp white logo on top. Each blurred copy follows
    // the letterforms so the halo wraps around every glyph (neon effect).
    Widget blurred(double sigma, double alpha) => ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: Opacity(
            opacity: alpha,
            child: SvgPicture.asset(
              'assets/logo/treino_logo.svg',
              height: size,
              colorFilter: ColorFilter.mode(palette.accent, BlendMode.srcIn),
            ),
          ),
        );

    return Stack(
      alignment: Alignment.center,
      children: [
        blurred(18.0, 0.7), // wide soft halo
        blurred(8.0, 0.6), // tighter punch around glyphs
        logo, // sharp logo
      ],
    );
  }
}
