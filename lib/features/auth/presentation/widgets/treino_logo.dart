import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../app/theme/app_palette.dart';

/// TREINO brand logo rendered from `assets/logo/treino_logo.svg`.
///
/// Uses `currentColor` inside the SVG, so the tint is controlled by [color].
/// Defaults to `palette.textPrimary`. The SVG aspect ratio is ~401:203
/// (width:height ≈ 1.97:1); [size] specifies the height in logical pixels.
class TreinoLogo extends StatelessWidget {
  const TreinoLogo({super.key, this.size = 56, this.color});

  /// Logo height in logical pixels.
  final double size;

  /// Tint color. Defaults to `palette.textPrimary`.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SvgPicture.asset(
      'assets/logo/treino_logo.svg',
      height: size,
      colorFilter: ColorFilter.mode(
        color ?? palette.textPrimary,
        BlendMode.srcIn,
      ),
    );
  }
}
