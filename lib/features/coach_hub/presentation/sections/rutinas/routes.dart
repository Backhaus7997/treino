import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/rutinas/athlete_routines_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/rutinas/rutinas_screen.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_page.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_item.dart';

/// Rutas e item de sidebar de la sección «Rutinas» del Coach Hub web.
///
/// La sección lista los alumnos vinculados; al tocar uno se abre el editor de
/// rutinas (`/routine-editor/:athleteId`, en `routine_editor/routes.dart`) para
/// asignarle una rutina. Cada sección posee su propio archivo para que los PRs
/// paralelos no choquen en `coach_hub_router.dart` ni en `sidebar_registry.dart`
/// (ADR-CHW-002). Usa `coachHubPage` (NoTransitionPage) para que el cambio de
/// sección sea instantáneo, sin overlap flash (bug W-COACH-NAV-01).
final List<RouteBase> rutinasRoutes = [
  GoRoute(
    path: '/rutinas',
    pageBuilder: (_, __) => coachHubPage(const RutinasScreen()),
  ),
  GoRoute(
    // Rutinas ya asignadas a un alumno → crear nueva o editar existentes.
    path: '/rutinas/:athleteId',
    pageBuilder: (_, state) => coachHubPage(
      AthleteRoutinesScreen(athleteId: state.pathParameters['athleteId']!),
    ),
  ),
];

const List<SidebarItem> rutinasSidebarItems = [
  SidebarItem(
    id: 'rutinas',
    label: 'Rutinas', // i18n: Fase W1
    route: '/rutinas',
    iconBuilder: _rutinasIcon,
    // RECURSOS — junto a Biblioteca (herramientas del PF para armar el entreno).
    group: SidebarGroup.recursos,
  ),
];

IconData _rutinasIcon() => TreinoIcon.sidebarRutinas;
