import 'package:flutter/material.dart';

import 'app_palette.dart';

/// Global app background: solid ink fill + two diagonal "dust" glows
/// (accent in upper-left, highlight in lower-right) — matches the brand
/// mockups exactly. Effect is intentionally subtle ("polvito"): low alpha
/// + small radius, so it hints at the palette without dominating.
///
/// Use as the outermost wrapper of any full-screen Scaffold body. Set
/// [glow] to false on screens that should be flat (e.g. modals).
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child, this.glow = true});

  final Widget child;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    if (!glow) {
      return Container(color: palette.bg, child: child);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Solid base
        Container(color: palette.bg),
        // Accent dust — top-left
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.7, -0.7),
              radius: 0.6,
              colors: [
                palette.accent.withValues(alpha: 0.07),
                Colors.transparent,
              ],
              stops: const [0.0, 0.8],
            ),
          ),
        ),
        // Highlight (magenta) dust — bottom-right
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.8, 0.85),
              radius: 0.6,
              colors: [
                palette.highlight.withValues(alpha: 0.07),
                Colors.transparent,
              ],
              stops: const [0.0, 0.8],
            ),
          ),
        ),
        child,
      ],
    );
  }
}
