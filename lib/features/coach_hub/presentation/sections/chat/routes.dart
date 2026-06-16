import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/shell/proximamente_screen.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_item.dart';

/// Rutas e item de sidebar de la sección «Chat» del Coach Hub web.
///
/// Placeholder de Fase W1 (ADR-CHW-008/009): la ruta renderiza
/// [ProximamenteScreen]; la screen real llega en Fase W2+. Cada sección posee
/// su propio archivo para que los PRs paralelos de W2+ no choquen en
/// `coach_hub_router.dart` ni en `sidebar_registry.dart` (ADR-CHW-002).
final List<RouteBase> chatRoutes = [
  GoRoute(
    path: '/chat',
    builder: (_, __) =>
        const ProximamenteScreen(label: 'Chat'), // i18n: Fase W1
  ),
  // TODO(W2+): wire real screen
];

const List<SidebarItem> chatSidebarItems = [
  SidebarItem(
    id: 'chat',
    label: 'Chat', // i18n: Fase W1
    route: '/chat',
    iconBuilder: _chatIcon,
    group: SidebarGroup.comunicacion,
  ),
];

IconData _chatIcon() => TreinoIcon.sidebarChat;
