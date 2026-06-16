import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/shell/proximamente_screen.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_item.dart';

/// Rutas e item de sidebar de la sección «Hábitos» del Coach Hub web.
///
/// Placeholder de Fase W1 (ADR-CHW-008/009): la ruta renderiza
/// [ProximamenteScreen]; la screen real llega en Fase W2+. Cada sección posee
/// su propio archivo para que los PRs paralelos de W2+ no choquen en
/// `coach_hub_router.dart` ni en `sidebar_registry.dart` (ADR-CHW-002).
final List<RouteBase> habitosRoutes = [
  GoRoute(
    path: '/habitos',
    builder: (_, __) =>
        const ProximamenteScreen(label: 'Hábitos'), // i18n: Fase W1
  ),
  // TODO(W2+): wire real screen
];

const List<SidebarItem> habitosSidebarItems = [
  SidebarItem(
    id: 'habitos',
    label: 'Hábitos', // i18n: Fase W1
    route: '/habitos',
    iconBuilder: _habitosIcon,
    group: SidebarGroup.wellness,
  ),
];

IconData _habitosIcon() => TreinoIcon.sidebarHabitos;
