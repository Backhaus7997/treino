import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/chat/chat_section_screen.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_page.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_item.dart';

/// Rutas e item de sidebar de la sección «Chat» del Coach Hub web.
///
/// W2 (2026-06-30): wireada con [ChatSectionScreen] — split-pane WhatsApp
/// Web style (lista izq + conversación der). V1 = solo texto; la V2 con
/// foto/video viene en un PR aparte. Cada sección posee su propio archivo
/// para que los PRs paralelos no choquen en `coach_hub_router.dart` ni en
/// `sidebar_registry.dart` (ADR-CHW-002).
final List<RouteBase> chatRoutes = [
  GoRoute(
    path: '/chat',
    pageBuilder: (_, __) => coachHubPage(const ChatSectionScreen()),
  ),
];

const List<SidebarItem> chatSidebarItems = [
  SidebarItem(
    id: 'chat',
    label: 'Chat', // i18n: Fase W1
    route: '/chat',
    iconBuilder: _chatIcon,
    group: SidebarGroup.gestion,
  ),
];

IconData _chatIcon() => TreinoIcon.sidebarChat;
