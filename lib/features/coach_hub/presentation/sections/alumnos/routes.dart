import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_page.dart';
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
    pageBuilder: (_, __) => coachHubPage(const AlumnosScreen()),
  ),
  GoRoute(
    path: '/alumnos/:id',
    // `?tab=` elige la seccion de entrada. Sin esto, entrar a un alumno DESDE
    // Nutricion caia en Resumen y habia que buscar la pestana a mano: el PF lo
    // pidio como «si entro a un alumno, que me mande directamente al apartado
    // para cargarle plan nutricional, derecho».
    //
    // Un query param y no un path nuevo: la ficha es la misma pantalla, y un
    // `/alumnos/:id/plan` obligaria a mantener una ruta por pestana.
    pageBuilder: (_, state) => coachHubPageAnimated(
      AlumnoDetailScreen(
        athleteId: state.pathParameters['id']!,
        tabInicial: state.uri.queryParameters['tab'],
      ),
    ),
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
