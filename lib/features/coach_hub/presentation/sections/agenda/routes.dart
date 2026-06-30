import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/agenda/agenda_web_screen.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_item.dart';

/// Rutas e item de sidebar de la sección «Agenda» del Coach Hub web.
///
/// PR1 (ADR-CHW-008/009): la ruta renderiza [AgendaWebScreen] — read-only
/// agenda viewer. Cada sección posee su propio archivo para que los PRs
/// paralelos no choquen en `coach_hub_router.dart` ni en
/// `sidebar_registry.dart` (ADR-CHW-002).
final List<RouteBase> agendaRoutes = [
  GoRoute(
    path: '/agenda',
    builder: (_, __) => const AgendaWebScreen(), // i18n
  ),
];

const List<SidebarItem> agendaSidebarItems = [
  SidebarItem(
    id: 'agenda',
    label: 'Agenda', // i18n: Fase W1
    route: '/agenda',
    iconBuilder: _agendaIcon,
    group: SidebarGroup.resumen,
  ),
];

IconData _agendaIcon() => TreinoIcon.sidebarAgenda;
