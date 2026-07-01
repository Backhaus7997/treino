import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/pagos_web_screen.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_item.dart';

/// Rutas e item de sidebar de la sección «Pagos» del Coach Hub web.
///
/// PR2a (ADR-CHW-008/009): la ruta renderiza [PagosScreen] (shell real).
/// Cada sección posee su propio archivo para que los PRs paralelos no choquen
/// en `coach_hub_router.dart` ni en `sidebar_registry.dart` (ADR-CHW-002).
final List<RouteBase> pagosRoutes = [
  GoRoute(
    path: '/pagos',
    builder: (_, __) => const PagosScreen(), // i18n: W4.2
  ),
];

const List<SidebarItem> pagosSidebarItems = [
  SidebarItem(
    id: 'pagos',
    label: 'Pagos', // i18n: Fase W1
    route: '/pagos',
    iconBuilder: _pagosIcon,
    group: SidebarGroup.negocio,
  ),
];

IconData _pagosIcon() => TreinoIcon.sidebarPagos;
