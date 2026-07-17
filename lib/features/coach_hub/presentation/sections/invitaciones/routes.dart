import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/invitaciones/invitaciones_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/invitaciones/solicitudes_providers.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_page.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_item.dart';

/// Rutas e item de sidebar de la sección «Invitaciones»/«Solicitudes» del
/// Coach Hub web.
///
/// Fase 4 (WU-04, ADR-F4-01): la ruta y el directorio se quedan `invitaciones`
/// por estabilidad (evita churn de router/tests); la copia de usuario es
/// «Solicitudes» (ver [InvitacionesScreen]). Cada sección posee su propio
/// archivo para que los PRs paralelos no choquen en `coach_hub_router.dart`
/// ni en `sidebar_registry.dart` (ADR-CHW-002).
///
/// WU-06 (ADR-F4-04): el item vuelve al grupo `gestion` (re-exposición
/// parcial de la reducción W2, justificada porque Fase 4 entrega la sección
/// real) con badge cableado a [invitacionesPendingCountProvider]. El
/// re-agregado al `sidebarRegistry` vive en `sidebar_registry.dart`.
final List<RouteBase> invitacionesRoutes = [
  GoRoute(
    path: '/invitaciones',
    pageBuilder: (_, __) => coachHubPage(const InvitacionesScreen()),
  ),
];

// No-const (a diferencia del resto de las secciones): `badgeProvider` apunta
// a `invitacionesPendingCountProvider`, un top-level `final` no evaluable en
// tiempo de compilación — `sidebar_registry.dart` deja de ser `const` por lo
// mismo (ver comentario ahí).
final List<SidebarItem> invitacionesSidebarItems = [
  SidebarItem(
    id: 'invitaciones',
    label: 'Solicitudes', // i18n: Fase 4 (ADR-F4-01/04, ex-"Invitaciones")
    route: '/invitaciones',
    iconBuilder: _invitacionesIcon,
    group: SidebarGroup.gestion,
    badgeProvider: invitacionesPendingCountProvider,
  ),
];

IconData _invitacionesIcon() => TreinoIcon.sidebarInvitaciones;
