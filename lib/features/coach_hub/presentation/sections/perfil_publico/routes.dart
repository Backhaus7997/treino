import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/perfil_publico/perfil_publico_screen.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_page.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_item.dart';

/// Rutas e item de sidebar de la sección «Perfil público» del Coach Hub web
/// (Fase 11, WU-01).
///
/// Muestra al PF logueado cómo lo ven los alumnos potenciales en TREINO
/// Coach Discovery — data real vía `userProfileProvider` (ADR-F11-01). Cada
/// sección posee su propio archivo para que los PRs paralelos no choquen en
/// `coach_hub_router.dart` ni en `sidebar_registry.dart` (ADR-CHW-002).
final List<RouteBase> perfilPublicoRoutes = [
  GoRoute(
    path: '/perfil-publico',
    pageBuilder: (_, __) => coachHubPage(const PerfilPublicoScreen()),
  ),
];

const List<SidebarItem> perfilPublicoSidebarItems = [
  SidebarItem(
    id: 'perfil-publico',
    label: 'Perfil público', // i18n: Fase 11
    route: '/perfil-publico',
    iconBuilder: _perfilPublicoIcon,
    group: SidebarGroup.gestion,
  ),
];

IconData _perfilPublicoIcon() => TreinoIcon.sidebarPerfilPublico;
