import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_palette.dart';

import 'content_max_width.dart';
import 'coach_hub_sidebar.dart';
import 'coach_hub_top_bar.dart';

/// Layout raíz del Coach Hub web (REQ-CHW-SHELL-001/002).
///
/// Único `Scaffold` del árbol: sidebar a la izquierda, top bar arriba y el
/// `child` (página de sección) en el área de contenido acotada por
/// [ContentMaxWidth]. Fondo `palette.bg` — dark mode, sin HEX literales.
///
/// W1.1 shipea SIN el guard responsivo (force-collapse < 1024, banner < 768);
/// eso se agrega en W1.3.4.
class CoachHubScaffold extends ConsumerWidget {
  const CoachHubScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    // TODO(W1.3): apply viewportFor() responsive guard.
    return Scaffold(
      backgroundColor: palette.bg,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CoachHubSidebar(),
          Expanded(
            child: Column(
              children: [
                const CoachHubTopBar(),
                Expanded(
                  child: ContentMaxWidth(maxWidth: 1240, child: child),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
