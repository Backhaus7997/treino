import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_palette.dart';

import 'content_max_width.dart';
import 'coach_hub_sidebar.dart';
import 'coach_hub_top_bar.dart';
import 'mobile_banner.dart';
import 'responsive.dart' as rsp;

/// Layout raíz del Coach Hub web (REQ-CHW-SHELL-001/002).
///
/// Único `Scaffold` del árbol: sidebar a la izquierda, top bar arriba y el
/// `child` (página de sección) en el área de contenido acotada por
/// [ContentMaxWidth]. Fondo `palette.bg` — dark mode, sin HEX literales.
///
/// Guard responsivo (ADR-CHW-004, REQ-CHW-RESPONSIVE-001/002):
/// - `< 768 px` → [MobileBanner] reemplaza todo el shell.
/// - `768–1279 px` (compact) → sidebar forzado a colapsado; el provider NO se
///   escribe, así el valor guardado se preserva al volver a desktop.
/// - `>= 1280 px` (desktop) → el sidebar respeta `sidebarCollapsedProvider`.
class CoachHubScaffold extends ConsumerWidget {
  const CoachHubScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final viewport = rsp.viewportFor(MediaQuery.sizeOf(context).width);

    if (viewport == rsp.Viewport.mobile) return const MobileBanner();

    final forceCollapsed = viewport == rsp.Viewport.compact;

    return Scaffold(
      backgroundColor: palette.bg,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CoachHubSidebar(collapsedOverride: forceCollapsed ? true : null),
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
