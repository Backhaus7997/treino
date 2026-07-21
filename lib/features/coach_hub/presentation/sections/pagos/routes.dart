import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/pagos_web_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_filtro_provider.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_page.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_item.dart';

/// Rutas e item de sidebar de la sección «Pagos» del Coach Hub web.
///
/// PR2a (ADR-CHW-008/009): la ruta renderiza [PagosScreen] (shell real).
/// Cada sección posee su propio archivo para que los PRs paralelos no choquen
/// en `coach_hub_router.dart` ni en `sidebar_registry.dart` (ADR-CHW-002).
final List<RouteBase> pagosRoutes = [
  GoRoute(
    path: '/pagos',
    pageBuilder: (_, __) => coachHubPage(const PagosScreen()), // i18n: W4.2
  ),
];

// No-const (a diferencia de otras secciones sin badge): `badgeProvider`
// apunta a `pagosBadgeCountProvider`, un top-level `final` no evaluable en
// tiempo de compilación — mismo patrón que `invitacionesSidebarItems`
// (ADR-F4-04). `sidebar_registry.dart` ya dejó de ser `const` por Solicitudes,
// así que sumar este provider no rompe la compilación (Fase 9 WU-08).
final List<SidebarItem> pagosSidebarItems = [
  SidebarItem(
    id: 'pagos',
    label: 'Pagos', // i18n: Fase W1
    route: '/pagos',
    iconBuilder: _pagosIcon,
    group: SidebarGroup.recursos,
    badgeProvider: pagosBadgeCountProvider,
  ),
];

IconData _pagosIcon() => TreinoIcon.sidebarPagos;
