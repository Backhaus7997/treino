import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_page.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_item.dart';

import 'coach_hub_dashboard_screen.dart';

/// Rutas e item de sidebar de la sección «Dashboard» del Coach Hub web.
///
/// Única sección de Fase W1 con screen real (no placeholder). La screen vive
/// en este mismo directorio (movida en W1.4, ADR-CHW-005/008). Mismo contrato
/// que el resto: aporta `dashboardRoutes` + `dashboardSidebarItems`.
final List<RouteBase> dashboardRoutes = [
  GoRoute(
    path: '/dashboard',
    pageBuilder: (_, __) => coachHubPage(const CoachHubDashboardScreen()),
  ),
];

const List<SidebarItem> dashboardSidebarItems = [
  SidebarItem(
    id: 'dashboard',
    label: 'Dashboard', // i18n: Fase W1
    route: '/dashboard',
    iconBuilder: _dashboardIcon,
    group: SidebarGroup.gestion,
  ),
];

IconData _dashboardIcon() => TreinoIcon.sidebarDashboard;
