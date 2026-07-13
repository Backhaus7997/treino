import 'package:go_router/go_router.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_page.dart';

import 'routine_editor_web_screen.dart';

/// Rutas contextuales del editor de rutinas web.
///
/// Viven DENTRO del `ShellRoute` — el PF ve el sidebar mientras arma la rutina.
/// No aportan item de sidebar (ADR-CHW-008): el acceso es contextual (botón
/// "Asignar rutina" / "Editar" en el detalle de alumno), no desde el menú
/// lateral. Mismo patrón que `legacy/routes.dart` (`/upload-plan`).
///
/// - `/routine-editor/:athleteId` → crear una rutina nueva para el alumno.
/// - `/routine-editor/:athleteId/:routineId` → editar una rutina existente
///   (solo rutinas "web-editables"; el editor rechaza las periodizadas).
final List<RouteBase> routineEditorRoutes = [
  GoRoute(
    path: '/routine-editor/:athleteId',
    pageBuilder: (_, state) => coachHubPage(
      RoutineEditorWebScreen(
        athleteId: state.pathParameters['athleteId']!,
      ),
    ),
  ),
  GoRoute(
    path: '/routine-editor/:athleteId/:routineId',
    pageBuilder: (_, state) => coachHubPage(
      RoutineEditorWebScreen(
        athleteId: state.pathParameters['athleteId']!,
        routineId: state.pathParameters['routineId'],
      ),
    ),
  ),
];
