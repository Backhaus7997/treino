import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../coach/application/trainer_link_providers.dart';
import '../../../../coach/domain/trainer_link.dart';
import '../../../../coach/domain/trainer_link_status.dart';

/// Tabs de la bandeja de Solicitudes (`/invitaciones`, ADR-F4-01/02).
///
/// Colapsan las 4 tabs del mockup (PENDIENTES/RESPONDIDAS/CONVERTIDAS/
/// ARCHIVADAS) en 3, honestas respecto al modelo real de [TrainerLink]: no
/// hay data para distinguir "respondida" de "convertida", ni sub-chips de
/// plan (ONLINE/PREMIUM/PREMIUM TRIM no existen).
enum SolicitudTab { pendientes, aceptadas, rechazadas }

/// Predicado puro (ADR-F4-02) — determina si [link] pertenece a [tab]:
/// - Pendientes: la solicitud todavía no fue resuelta (`status == pending`).
/// - Aceptadas: el vínculo nació de un accept, sin importar si luego se
///   pausó (`status == active || status == paused`) — es historial
///   read-only, no gestión de vínculos (eso es Alumnos).
/// - Rechazadas: el vínculo terminó (`status == terminated`), sea porque el
///   PF declinó la solicitud o porque un vínculo activo se dio de baja
///   luego. El modelo no distingue el origen del terminate.
bool matchesSolicitudTab(TrainerLink link, SolicitudTab tab) => switch (tab) {
      SolicitudTab.pendientes => link.status == TrainerLinkStatus.pending,
      SolicitudTab.aceptadas => link.status == TrainerLinkStatus.active ||
          link.status == TrainerLinkStatus.paused,
      SolicitudTab.rechazadas => link.status == TrainerLinkStatus.terminated,
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
