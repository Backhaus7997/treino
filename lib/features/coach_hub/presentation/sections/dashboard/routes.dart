import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_dashboard_screen.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_item.dart';

/// Rutas e item de sidebar de la sección «Dashboard» del Coach Hub web.
///
/// Única sección de Fase W1 con screen real (no placeholder). La screen se
/// importa desde su ubicación actual; en W1.4 se moverá a `sections/dashboard/`
/// (ADR-CHW-008). Mismo contrato que el resto: aporta `dashboardRoutes` +
/// `dashboardSidebarItems`.
final List<RouteBase> dashboardRoutes = [
  GoRoute(
    path: '/dashboard',
    builder: (_, __) => const CoachHubDashboardScreen(),
  ),
];

const List<SidebarItem> dashboardSidebarItems = [
  SidebarItem(
    id: 'dashboard',
    label: 'Dashboard', // i18n: Fase W1
    route: '/dashboard',
    iconBuilder: _dashboardIcon,
    group: SidebarGroup.resumen,
  ),
];

IconData _dashboardIcon() => TreinoIcon.sidebarDashboard;
