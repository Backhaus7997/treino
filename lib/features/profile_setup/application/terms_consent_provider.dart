import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart';

/// ¿Esta cuenta tiene que aceptar Términos y Privacidad en el último paso del
/// alta? (QA-AUTH-001, issue #434).
///
/// Se decide por EVIDENCIA de consentimiento —`termsAcceptedAt` en el
/// perfil—, no por si el perfil existe. Hasta sep-2026 la pregunta era
/// `userProfileProvider.valueOrNull == null`, apoyada en que una cuenta OAuth
/// llega al alta sin `users/{uid}`. Es falso: `signInWithGoogle` y
/// `signInWithApple` crean el doc con `createIfAbsent` ANTES de llegar acá.
/// Cuando ese create andaba, el checkbox no salía y el consentimiento no se
/// registraba nunca; salía sólo cuando el create fallaba. Medido en
/// producción: de las 5 altas con Google/Apple del 16 al 22/09, las 2 donde
/// el create anduvo quedaron con `termsAcceptedAt` en null.
///
/// Tres respuestas, no dos:
/// - `true`: no hay evidencia. Sin doc, o doc sin `termsAcceptedAt`: altas
///   con Google/Apple, cuentas legacy, y las altas desde la web
///   (`ensureAthleteProfile` no escribe el campo).
/// - `false`: hay evidencia. El alta por email la estampa en el registro,
///   detrás del checkbox de `register_screen.dart`.
/// - `null`: todavía no se sabe —el perfil no cargó, o el stream falló sin
///   un valor previo—. NO es `false`, y quien lee decide qué hacer: la
///   pantalla muestra el checkbox (preguntar de más no le cuesta nada a
///   nadie; preguntar de menos es un alta sin consentimiento).
///
/// Esto sale de lo que OBSERVA la app, que puede ser la caché local. Sirve
/// para decidir qué mostrar, no para escribir: antes de estampar, el submit
/// confirma contra el servidor todo lo que no sea `false`
/// (`UserRepository.getFromServer`).
final termsConsentRequiredProvider = Provider<bool?>((ref) {
  return ref.watch(
    userProfileProvider.select((perfil) {
      if (!perfil.hasValue) return null;
      return perfil.value?.termsAcceptedAt == null;
    }),
  );
});
