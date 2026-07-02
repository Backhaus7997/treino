import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/biblioteca_web_screen.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_item.dart';

/// Rutas e item de sidebar de la sección «Biblioteca» del Coach Hub web.
///
/// Fase W5.3: la ruta renderiza [BibliotecaWebScreen] (2 tabs: Ejercicios +
/// Templates Rutinas). Cada sección posee su propio archivo para que los PRs
/// de fases distintas no choquen en `coach_hub_router.dart` ni en
/// `sidebar_registry.dart` (ADR-CHW-002).
final List<RouteBase> bibliotecaRoutes = [
  GoRoute(
    path: '/biblioteca',
    builder: (_, __) => const BibliotecaWebScreen(),
  ),
];

const List<SidebarItem> bibliotecaSidebarItems = [
  SidebarItem(
    id: 'biblioteca',
    label: 'Biblioteca', // i18n: Fase W1
    route: '/biblioteca',
    iconBuilder: _bibliotecaIcon,
    group: SidebarGroup.recursos,
  ),
];

IconData _bibliotecaIcon() => TreinoIcon.sidebarBiblioteca;
