import 'package:flutter/material.dart';

import 'app_palette.dart';

class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(color: palette.bg, child: child);
  }
}
