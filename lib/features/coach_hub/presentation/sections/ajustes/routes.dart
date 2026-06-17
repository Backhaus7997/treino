import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/ajustes_screen.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_item.dart';

/// Rutas e item de sidebar de la sección «Ajustes» (Configuración) del Coach
/// Hub web.
///
/// Fase W3.1: `/ajustes` renderiza [AjustesScreen] (scaffold de Configuración +
/// tab Cuenta). Cada sección posee su propio archivo para que los PRs paralelos
/// no choquen en `coach_hub_router.dart` ni en `sidebar_registry.dart`
/// (ADR-CHW-002).
final List<RouteBase> ajustesRoutes = [
  GoRoute(path: '/ajustes', builder: (_, __) => const AjustesScreen()),
];

const List<SidebarItem> ajustesSidebarItems = [
  SidebarItem(
    id: 'ajustes',
    label: 'Ajustes', // i18n: Fase W1
    route: '/ajustes',
    iconBuilder: _ajustesIcon,
    group: SidebarGroup.ajustes,
  ),
];

IconData _ajustesIcon() => TreinoIcon.sidebarAjustes;
