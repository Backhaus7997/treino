import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../coach/application/trainer_link_providers.dart';
import '../../../../coach/domain/trainer_link.dart';
import '../../../../coach/domain/trainer_link_status.dart';

/// Tabs de la bandeja de Solicitudes (`/invitaciones`, ADR-F4-01/02).
///
/// Colapsan las 4 tabs del mockup (PENDIENTES/RESPONDIDAS/CONVERTIDAS/
/// ARCHIVADAS) en 2, honestas respecto al modelo real de [TrainerLink]: no
/// hay data para distinguir "respondida" de "convertida", ni sub-chips de
/// plan (ONLINE/PREMIUM/PREMIUM TRIM no existen).
///
/// Hubo una tercera, RECHAZADAS, que filtraba por `status == terminated`. Se
/// sacó junto con la persistencia del rechazo: una solicitud rechazada (o
/// cancelada por el alumno) ya no deja documento — la borra
/// `purge-rejected-link.ts` apenas sale la notificación.
///
/// Lo que ese tab mostraba NO era sólo rechazos, y por eso su baja tiene un
/// costo que conviene decir: `terminated` es también el fin de un vínculo
/// REAL (terminate / switched_trainer). Esos docs siguen existiendo —tienen
/// pagos y sesiones colgando— y desde este cambio no tienen superficie en el
/// Coach Hub web. Fue una decisión de producto, no un descuido.
enum SolicitudTab { pendientes, aceptadas }

/// Predicado puro (ADR-F4-02) — determina si [link] pertenece a [tab]:
/// - Pendientes: la solicitud todavía no fue resuelta (`status == pending`).
/// - Aceptadas: el vínculo nació de un accept, sin importar si luego se
///   pausó (`status == active || status == paused`) — es historial
///   read-only, no gestión de vínculos (eso es Alumnos).
///
/// `terminated` no matchea ningún tab: los rechazos ya no se persisten, y los
/// vínculos reales terminados quedan fuera de esta bandeja a propósito.
bool matchesSolicitudTab(TrainerLink link, SolicitudTab tab) => switch (tab) {
      SolicitudTab.pendientes => link.status == TrainerLinkStatus.pending,
      SolicitudTab.aceptadas => link.status == TrainerLinkStatus.active ||
          link.status == TrainerLinkStatus.paused,
    };

/// Tab seleccionado en la bandeja de Solicitudes. Default: Pendientes — la
/// sección es una bandeja de triage (plan-fase4.md §3).
///
/// Nombrado sin `_` (a diferencia de `_filtroProvider` en `alumnos_screen`
/// dart): lo consume `InvitacionesScreen`, un archivo distinto dentro de la
/// misma sección — Dart no tiene privacidad a nivel de directorio/feature,
/// solo a nivel de archivo.
final solicitudTabProvider =
    StateProvider.autoDispose<SolicitudTab>((_) => SolicitudTab.pendientes);

/// Conteo de solicitudes pendientes — badge del sidebar (ADR-F4-04).
///
/// `null` mientras [trainerLinksStreamProvider] está en loading/error (el
/// `_Badge` del kit no renderiza nada si el count es `null`); en `data`,
/// cuenta cuántos links tienen `status == pending`.
final invitacionesPendingCountProvider = Provider.autoDispose<int?>((ref) {
  final links = ref.watch(trainerLinksStreamProvider).valueOrNull;
  if (links == null) return null;
  return links.where((l) => l.status == TrainerLinkStatus.pending).length;
});
