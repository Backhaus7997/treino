import '../../features/auth/presentation/legal/legal_content.dart';

/// El `mailto:` con el que alguien le pide al equipo ser entrenador.
///
/// No hay alta self-service de PF: el rol `trainer` lo asigna el equipo a mano
/// por Admin SDK. Por eso todo acceso «Quiero ser entrenador» —la Welcome y la
/// pantalla de no-autorizado del Coach Hub— termina en este mismo mail, y vive
/// en un solo lugar para que los dos no diverjan en dirección o asunto.
///
/// `query:` + `encodeComponent`, NO `queryParameters`: éste codifica el espacio
/// como `+`, que en un `mailto:` los clientes muestran literal.
Uri mailtoQuieroSerEntrenador(String asunto) => Uri(
      scheme: 'mailto',
      path: kLegalContactEmail,
      query: 'subject=${Uri.encodeComponent(asunto)}',
    );
