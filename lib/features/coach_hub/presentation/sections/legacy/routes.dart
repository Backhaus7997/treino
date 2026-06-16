import 'package:go_router/go_router.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_upload_plan_screen.dart';

/// Rutas legacy del flujo de carga de planes (REQ-CHW-UPLOADPLAN-001).
///
/// Viven DENTRO del `ShellRoute` — el PF ve el sidebar mientras sube un plan.
/// No aportan items de sidebar (ADR-CHW-008): el acceso es contextual (botón en
/// otra pantalla), no desde el menú lateral.
final List<RouteBase> legacyRoutes = [
  GoRoute(
    path: '/upload-plan',
    builder: (_, __) => const CoachHubUploadPlanScreen(),
  ),
  GoRoute(
    path: '/upload-plan/preview',
    builder: (_, __) => const CoachHubPlanPreviewScreen(),
  ),
];
