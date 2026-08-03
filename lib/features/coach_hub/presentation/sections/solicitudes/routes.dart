import 'package:go_router/go_router.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_page.dart';

import 'solicitudes_screen.dart';

/// Rutas de la sección «Solicitudes» del Coach Hub web.
///
/// A diferencia del resto de las secciones (ver ADR-CHW-002), esta NO tiene
/// item de sidebar — se llega acá solo desde la campana de notificaciones
/// en el top bar (mirror del bell mobile → `FriendRequestsInboxScreen`, que
/// tampoco tiene tab de nav propia).
final List<RouteBase> solicitudesRoutes = [
  GoRoute(
    path: '/solicitudes',
    pageBuilder: (_, __) => coachHubPage(const SolicitudesScreen()),
  ),
];
