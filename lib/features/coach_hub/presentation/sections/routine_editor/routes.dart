import 'package:go_router/go_router.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_page.dart';

import 'routine_editor_web_screen.dart';

/// Ruta contextual del editor de rutinas web (asignar rutina a un alumno).
///
/// Vive DENTRO del `ShellRoute` — el PF ve el sidebar mientras arma la rutina.
/// No aporta item de sidebar (ADR-CHW-008): el acceso es contextual (botón
/// "Asignar rutina" en el detalle de alumno), no desde el menú lateral.
/// Mismo patrón que `legacy/routes.dart` (`/upload-plan`).
final List<RouteBase> routineEditorRoutes = [
  GoRoute(
    path: '/routine-editor/:athleteId',
    pageBuilder: (_, state) => coachHubPage(
      RoutineEditorWebScreen(
        athleteId: state.pathParameters['athleteId']!,
      ),
    ),
  ),
];
