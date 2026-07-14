import 'package:go_router/go_router.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/pricing_screen.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_page.dart';

/// Ruta de la pricing page del paywall PF→TREINO (Fase 7, PR3 UI).
///
/// NO es una sección del sidebar — es un sub-flujo que se abre desde el botón
/// "CAMBIAR PLAN" de Facturación (tab Ajustes). Por eso vive en su propio
/// archivo pero sin `SidebarItem`. Distinta de `/planes` («Planes
/// comerciales», que son los planes que el PF le vende a SUS alumnos).
final List<RouteBase> facturacionPlanesRoutes = [
  GoRoute(
    path: '/facturacion/planes',
    pageBuilder: (_, __) => coachHubPage(const PricingScreen()),
  ),
];
