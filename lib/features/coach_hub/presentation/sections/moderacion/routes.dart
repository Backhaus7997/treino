import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/moderacion/moderacion_screen.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_page.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_item.dart';
import 'package:treino/features/moderation/application/moderation_queue_providers.dart';

/// Rutas e item de sidebar de la cola de moderación.
///
/// Cada sección posee su propio archivo para que los PRs paralelos no choquen
/// en `coach_hub_router.dart` ni en `sidebar_registry.dart` (ADR-CHW-002).
final List<RouteBase> moderacionRoutes = [
  GoRoute(
    path: '/moderacion',
    pageBuilder: (_, __) => coachHubPage(const ModeracionScreen()),
  ),
];

/// El ítem aparece SÓLO con el claim `moderator`, vía [isModeratorProvider].
///
/// Eso es UI, no control de acceso: la ruta existe igual y se puede escribir a
/// mano en la barra del navegador. Lo que protege de verdad es
/// `assertModerator` del otro lado de los callables, donde hay Admin SDK y las
/// rules no participan. La pantalla, además, no muestra nada sin el claim.
// `final` y no `const`: `visibleProvider` referencia un provider, que no es
// constante en tiempo de compilación. Mismo caso que `invitacionesSidebarItems`
// con su `badgeProvider`.
final List<SidebarItem> moderacionSidebarItems = [
  SidebarItem(
    id: 'moderacion',
    label: 'Moderación', // i18n: Fase W3
    route: '/moderacion',
    iconBuilder: _moderacionIcon,
    group: SidebarGroup.cuenta,
    visibleProvider: isModeratorProvider,
  ),
];

/// `shieldCheck` y no `report` (la bandera): reportar es lo que hace el
/// visitante sobre contenido ajeno, y esto es lo contrario — el lugar donde se
/// revisa lo reportado.
IconData _moderacionIcon() => TreinoIcon.shieldCheck;
