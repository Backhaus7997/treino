import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';

/// `refreshListenable` del router del Coach Hub.
///
/// Es el mismo `RouterRefreshNotifier` que usa el router de mobile: ya escucha
/// auth, perfil, email gate y el pendiente de escrituras de `users/{uid}`
/// (`userProfileHasPendingWritesProvider`), que es lo que necesita el gate de
/// onboarding del Hub (`done && !pendiente`) para re-evaluarse cuando el
/// servidor confirma la escritura.
///
/// Antes el Hub tenía su propio ping del pendiente porque el notifier
/// compartido no lo escuchaba. Desde #1335 sí lo escucha (el gate de edad de
/// mobile tiene la misma necesidad), así que mantener un segundo ping
/// duplicaría el refresh del router en cada ack.
final coachHubRouterRefreshProvider = Provider<Listenable>(
  (ref) => ref.watch(routerRefreshNotifierProvider),
);
