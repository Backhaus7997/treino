import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_item.dart';

import 'alumno_detail_screen.dart';
import 'alumnos_screen.dart';

/// Rutas e item de sidebar de la sección «Alumnos» del Coach Hub web.
///
/// Fase W2: `/alumnos` es el roster ([AlumnosScreen], PR1) y `/alumnos/:id` el
/// detalle del alumno ([AlumnoDetailScreen], PR2 — tabs; sólo Progreso real por
/// ahora). Cada sección posee su propio archivo para que los PRs paralelos no
/// choquen en `coach_hub_router.dart` (ADR-CHW-002/008).
final List<RouteBase> alumnosRoutes = [
  GoRoute(
    path: '/alumnos',
    builder: (_, __) => const AlumnosScreen(),
  ),
  GoRoute(
    path: '/alumnos/:id',
    builder: (_, state) =>
        AlumnoDetailScreen(athleteId: state.pathParameters['id']!),
  ),
];

const List<SidebarItem> alumnosSidebarItems = [
  SidebarItem(
    id: 'alumnos',
    label: 'Alumnos', // i18n: Fase W1
    route: '/alumnos',
    iconBuilder: _alumnosIcon,
    group: SidebarGroup.gestion,
  ),
];

IconData _alumnosIcon() => TreinoIcon.sidebarAlumnos;
