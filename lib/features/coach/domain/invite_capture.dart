import '../../../core/utils/deep_link_destination.dart';

/// El PF de una invitación que venga en [uri], o `null` si [uri] no es una.
///
/// ─── Por qué existe separado del router ─────────────────────────────────────
///
/// `/abrir/alumno` redirige a `/home` y descarta la query. El comentario que
/// tenía al lado explicaba por qué eso estaba bien: «se pierde el destino
/// puntual, que es aceptable mientras los dos destinos sean la home de cada
/// rol». Una invitación rompe ese supuesto — su destino NO es la home, es un
/// PF concreto, y ese dato tiene que sobrevivir.
///
/// Peor todavía con la sesión cerrada: ahí el gate de auth gana antes que la
/// ruta y manda a `/welcome`, así que ni siquiera llega a correr el redirect de
/// `/abrir/alumno`. Por eso la captura va en el redirect de NIVEL SUPERIOR, que
/// corre para toda navegación, y por eso esta decisión es una función pura: se
/// puede testear sin router, sin auth y sin disco.
String? trainerIdDeInvitacion(Uri uri) {
  final destino = DeepLinkDestination.fromQuery(uri.queryParameters);
  if (destino?.to != DeepLinkTo.invitacion) return null;
  return destino!.trainerId;
}
