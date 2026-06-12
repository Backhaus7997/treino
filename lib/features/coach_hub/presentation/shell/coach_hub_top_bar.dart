import 'package:flutter/material.dart';
import 'package:treino/app/theme/app_palette.dart';

/// Stub del top bar (64 px). Existe sólo para que el `CoachHubScaffold` compile
/// en W1.1. El contenido real (toggle + breadcrumb + bell + user menu) se
/// implementa en W1.3.1.
class CoachHubTopBar extends StatelessWidget {
  const CoachHubTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(height: 64, color: palette.bg);
  }
}
