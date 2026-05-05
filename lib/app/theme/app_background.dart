import 'package:flutter/material.dart';

import 'app_palette.dart';

/// Global app background: ink fill + subtle radial accent glow on the
/// upper-left, matching the brand mockups (Welcome, Login, Splash, etc.).
///
/// Use as the outermost wrapper of any full-screen Scaffold body or as the
/// ShellRoute backdrop. Set [glow] to false on screens that should be flat.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child, this.glow = true});

  final Widget child;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      decoration: glow
          ? BoxDecoration(
              color: palette.bg,
              gradient: RadialGradient(
                center: const Alignment(-0.6, -0.4),
                radius: 0.9,
                colors: [
                  palette.accent.withValues(alpha: 0.14),
                  palette.bg,
                ],
                stops: const [0.0, 0.7],
              ),
            )
          : BoxDecoration(color: palette.bg),
      child: child,
    );
  }
}
