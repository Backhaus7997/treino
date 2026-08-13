import 'package:go_router/go_router.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/paywall_preview_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/pricing_screen.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_page.dart';

/// Rutas del paywall PF→TREINO (Fase 7, PR3 UI).
///
/// NO son secciones del sidebar — `/facturacion/planes` es un sub-flujo que se
/// abre desde "CAMBIAR PLAN" de Facturación. Distinta de `/planes` («Planes
/// comerciales», que son los planes que el PF le vende a SUS alumnos).
///
/// `/facturacion/preview*` son rutas de DEV/SMOKE para ver los modals que se
/// disparan desde el backend (bloqueo N+1, keep-2) que aún no existe (PR4/PR5).
/// Sin item de sidebar — solo por URL directa. Quitables cuando el trigger
/// real esté cableado.
final List<RouteBase> facturacionPlanesRoutes = [
  GoRoute(
    path: '/facturacion/planes',
    pageBuilder: (_, __) => coachHubPage(const PricingScreen()),
  ),
  GoRoute(
    path: '/facturacion/preview',
    pageBuilder: (_, __) => coachHubPage(const PaywallPreviewScreen()),
  ),
  GoRoute(
    path: '/facturacion/preview/keep2',
    pageBuilder: (_, __) => coachHubPage(const KeepStudentsPreview()),
  ),
];
