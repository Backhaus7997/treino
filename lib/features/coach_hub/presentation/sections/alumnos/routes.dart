import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_item.dart';

import 'alumnos_screen.dart';

/// Rutas e item de sidebar de la sección «Alumnos» del Coach Hub web.
///
/// Fase W2 PR1: la ruta `/alumnos` ya renderiza el roster real
/// ([AlumnosScreen]). El detalle `/alumnos/:id` (mini-CRM por alumno) llega en
/// PRs siguientes. Cada sección posee su propio archivo para que los PRs
/// paralelos no choquen en `coach_hub_router.dart` (ADR-CHW-002/008).
final List<RouteBase> alumnosRoutes = [
  GoRoute(
    path: '/alumnos',
    builder: (_, __) => const AlumnosScreen(),
  ),
  // TODO(W2 PR2+): GoRoute('/alumnos/:id') → detalle del alumno
];

const List<SidebarItem> alumnosSidebarItems = [
  SidebarItem(
    id: 'alumnos',
    label: 'Alumnos', // i18n: Fase W1
    route: '/alumnos',
    iconBuilder: _alumnosIcon,
    group: SidebarGroup.alumnos,
  ),
];

IconData _alumnosIcon() => TreinoIcon.sidebarAlumnos;
