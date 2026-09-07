import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/theme/app_palette.dart';

/// TREINO brand logo rendered from `assets/logo/treino_logo.svg`.
///
/// Vive en `core/` —y no en `features/auth/`, donde nació— porque la marca no
/// es de una feature: la usan las pantallas de auth Y el sidebar del Coach Hub.
/// Mismo criterio que `core/widgets/exercise_asset_image.dart`.
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
    // Los sigmas ESCALAN con [size]. Estaban clavados en 18 y 8, que es lo
    // correcto para los 120 px de la pantalla de bienvenida —de donde salieron—
    // pero convierten el halo en una mancha en cualquier uso chico: a 22 px el
    // desenfoque medía casi el alto del logo.
    //
    // Las constantes son los mismos 18/120 y 8/120, así que a 120 el resultado
    // es idéntico al de antes y ningún uso existente cambia.
    double sigmaPara(double base) => base / 120.0 * size;

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
        blurred(sigmaPara(18.0), 0.7), // wide soft halo
        blurred(sigmaPara(8.0), 0.6), // tighter punch around glyphs
        logo, // sharp logo
      ],
    );
  }
}
