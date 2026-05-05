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

    // Accent halo — radial gradient sized to ~2.4x the logo width, behind
    // the SVG so it reads as ambient light spilling from the brand.
    return Stack(
      alignment: Alignment.center,
      children: [
        IgnorePointer(
          child: Container(
            width: size * 4.5,
            height: size * 2.4,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  palette.accent.withValues(alpha: 0.35),
                  palette.accent.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.7],
              ),
            ),
          ),
        ),
        logo,
      ],
    );
  }
}
