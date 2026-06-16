import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_palette.dart';

import 'sidebar_item.dart';
import 'sidebar_registry.dart';

/// Breadcrumb del top bar (REQ-CHW-TOPBAR-002).
///
/// Deriva el trail desde la ruta actual (`GoRouterState.uri`) matcheando cada
/// segmento acumulado contra `sidebarRegistry` por `item.route`. En W1 las
/// rutas son de un solo nivel, así que el trail es un único segmento (la
/// sección actual). Rutas sin match en el registro (eg. `/upload-plan`) no
/// renderizan nada — fallback elegante, sin crash.
class CoachHubBreadcrumb extends StatelessWidget {
  const CoachHubBreadcrumb({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final trail = _trailFor(GoRouterState.of(context).uri.path);
    if (trail.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    for (var i = 0; i < trail.length; i++) {
      if (i > 0) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '›',
            style: TextStyle(color: palette.textMuted, fontSize: 14),
          ),
        ));
      }
      final isLast = i == trail.length - 1;
      children.add(Flexible(
        child: Text(
          trail[i],
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isLast ? palette.textPrimary : palette.textMuted,
            fontSize: 14,
            fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  /// Labels de las secciones cuyas rutas matchean los segmentos acumulados.
  List<String> _trailFor(String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty);
    final trail = <String>[];
    var acc = '';
    for (final seg in segments) {
      acc = '$acc/$seg';
      for (final SidebarItem item in sidebarRegistry) {
        if (item.route == acc) {
          trail.add(item.label);
          break;
        }
      }
    }
    return trail;
  }
}
