import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/nutricion/nutricion_screen.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_page.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_item.dart';

/// Rutas e item de sidebar de la sección «Nutrición» del Coach Hub web.
///
/// Fase 6 (WU-04): la ruta renderiza [NutricionScreen] — overview
/// cross-alumno de planes de nutrición. Cada sección posee su propio archivo
/// para que los PRs paralelos no choquen en `coach_hub_router.dart` ni en
/// `sidebar_registry.dart` (ADR-CHW-002).
///
/// Fase 6 (WU-06, ADR-F6-07): el item vuelve a pertenecer a
/// [SidebarGroup.recursos] — el único grupo que `sidebar_registry.dart`
/// efectivamente renderea junto a `gestion` — para que la overview sea
/// alcanzable por navegación, no solo por URL directa. `wellness` (grupo
/// original pre-W2) queda legacy y sin renderear.
final List<RouteBase> nutricionRoutes = [
  GoRoute(
    path: '/nutricion',
    pageBuilder: (_, __) => coachHubPage(const NutricionScreen()),
  ),
];

const List<SidebarItem> nutricionSidebarItems = [
  SidebarItem(
    id: 'nutricion',
    label: 'Nutrición', // i18n: Fase W1
    route: '/nutricion',
    iconBuilder: _nutricionIcon,
    group: SidebarGroup.recursos,
  ),
];

IconData _nutricionIcon() => TreinoIcon.sidebarNutricion;
