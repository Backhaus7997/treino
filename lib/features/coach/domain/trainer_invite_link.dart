/// Contrato del link de invitación que un PF le comparte a un alumno.
///
/// ─── Por qué cuelga de `/abrir/` y no de una ruta nueva ─────────────────────
///
/// `/abrir/*` ya es el espacio de deep links del proyecto: está registrado en
/// `web/well-known/apple-app-site-association` y en el `intent-filter` con
/// `autoVerify` del `AndroidManifest`, tiene página de fallback para quien lo
/// abre desde una computadora (`web/abrir/alumno.html`) y su query `?to=` ya la
/// parsea [DeepLinkDestination]. Estrenar un host o un path propio significaría
/// re-registrar universal links en las dos tiendas para no ganar nada.
///
/// La mitad que PARSEA vive en `core/utils/deep_link_destination.dart`. Las dos
/// están clavadas por tests sobre el mismo literal, igual que el deep link del
/// reporte mensual: si alguien cambia el formato de un lado, el otro se pone
/// rojo en vez de generar links que nadie puede abrir.
///
/// ─── Qué viaja en la URL ────────────────────────────────────────────────────
///
/// El uid del PF, y nada más. No es un secreto —cualquier alumno vinculado ya
/// lo conoce, y aparece en los docs de `trainer_links` que ese alumno lee— pero
/// tampoco es una credencial: por sí solo no vincula a nadie. Quien abre el
/// link tiene que estar autenticado y confirmar; el vínculo lo crea el flujo
/// normal de `trainer_links`, con sus reglas.
///
/// Un token de invitación de un solo uso sería más estricto (permitiría
/// caducidad y revocación), pero necesita colección y callable propios. Está
/// anotado como el siguiente paso, no resuelto acá.
library;

/// Host público del Coach Hub. Es el mismo que registran los universal links.
const String kTreinoDeepLinkHost = 'app.gettreino.com';

/// Página de fallback para ALUMNOS. La de PFs es `/abrir/profe`.
const String kTreinoAthleteDeepLinkPath = '/abrir/alumno';

/// El link que el PF comparte para que un alumno se vincule con él.
///
/// Devuelve `null` si [trainerId] viene vacío: un link de invitación sin PF no
/// invita a nada, y es mejor no ofrecer nada para copiar que ofrecer algo que
/// del otro lado no resuelve.
String? buildTrainerInviteLink(String trainerId) {
  if (trainerId.trim().isEmpty) return null;
  return Uri.https(kTreinoDeepLinkHost, kTreinoAthleteDeepLinkPath, {
    'to': 'invitacion',
    'pf': trainerId,
  }).toString();
}
