import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/invitaciones/invitaciones_screen.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_page.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_item.dart';

/// Rutas e item de sidebar de la sección «Invitaciones»/«Solicitudes» del
/// Coach Hub web.
///
/// Fase 4 (WU-04, ADR-F4-01): la ruta y el directorio se quedan `invitaciones`
/// por estabilidad (evita churn de router/tests); la copia de usuario es
/// «Solicitudes» (ver [InvitacionesScreen]). Cada sección posee su propio
/// archivo para que los PRs paralelos no choquen en `coach_hub_router.dart`
/// ni en `sidebar_registry.dart` (ADR-CHW-002). El re-cableo del item de
/// sidebar (badge de pendientes) lo hace WU-06 — NO tocar acá.
final List<RouteBase> invitacionesRoutes = [
  GoRoute(
    path: '/invitaciones',
    pageBuilder: (_, __) => coachHubPage(const InvitacionesScreen()),
  ),
];

const List<SidebarItem> invitacionesSidebarItems = [
  SidebarItem(
    id: 'invitaciones',
    label: 'Invitaciones', // i18n: Fase W1
    route: '/invitaciones',
    iconBuilder: _invitacionesIcon,
    group: SidebarGroup.alumnos,
  ),
];

IconData _invitacionesIcon() => TreinoIcon.sidebarInvitaciones;
