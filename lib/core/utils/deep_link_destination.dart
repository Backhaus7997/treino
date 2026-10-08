/// Un destino fino dentro de la app o del Coach Hub, codificado en el `to`
/// (y opcionalmente `id`) que los mails transaccionales agregan al CTA del
/// entrenador — ver `functions/src/mail/templates.ts` (`trainerEntry`).
///
/// Esto es SOLO el parsing. Que hacer con cada valor —a qué RUTA mapea— es
/// decisión de cada router: mobile y Coach Hub web tienen paths distintos
/// para el mismo destino (`/coach/athlete/:id` vs `/alumnos/:id`), así que
/// compartir esa parte sería forzar una coincidencia que no existe. Cada
/// router tiene su propio switch de acá para adelante.
enum DeepLinkTo {
  facturacion,
  agenda,
  solicitudes,
  alumno,

  /// Invitación de un PF a un alumno.
  ///
  /// A diferencia de los otros cuatro —que llegan de un mail nuestro a alguien
  /// que YA es usuario—, éste lo comparte el PF por donde quiera: WhatsApp,
  /// mail, papel. Lo puede abrir alguien sin cuenta, sin app, o vinculado a
  /// otro PF. Los casos los resuelve quien lo consume; acá sólo se parsea.
  invitacion,
}

class DeepLinkDestination {
  const DeepLinkDestination(this.to, [this.athleteId, this.trainerId]);

  final DeepLinkTo to;

  /// Solo tiene valor cuando `to == DeepLinkTo.alumno`. El constructor no lo
  /// exige porque Dart no tiene unions taggeados nativos, pero
  /// [fromQuery] SÍ hace cumplir el invariante: nunca devuelve un
  /// `DeepLinkTo.alumno` sin `athleteId`.
  final String? athleteId;

  /// Solo tiene valor cuando `to == DeepLinkTo.invitacion`: el PF que la
  /// generó. Mismo invariante que [athleteId] y por la misma razón — una
  /// invitación sin PF no es una invitación, es el default disfrazado.
  final String? trainerId;

  /// Devuelve `null` si no hay un `to` reconocido, o si `to=alumno` llegó
  /// sin `id` — un destino de alumno sin a qué alumno apuntar no es un
  /// destino, es el default disfrazado de uno.
  static DeepLinkDestination? fromQuery(Map<String, String> query) {
    switch (query['to']) {
      case 'facturacion':
        return const DeepLinkDestination(DeepLinkTo.facturacion);
      case 'agenda':
        return const DeepLinkDestination(DeepLinkTo.agenda);
      case 'solicitudes':
        return const DeepLinkDestination(DeepLinkTo.solicitudes);
      case 'alumno':
        final id = query['id'];
        return (id == null || id.isEmpty)
            ? null
            : DeepLinkDestination(DeepLinkTo.alumno, id);
      case 'invitacion':
        // `pf` y no `id`: los dos parámetros conviven en el mismo espacio de
        // query y significan cosas distintas —un alumno y un entrenador—.
        // Reusar `id` haría que un link a medio editar («to=alumno&id=X»
        // pasado a «to=invitacion») resolviera a un destino válido con el
        // identificador equivocado, que es peor que no resolver.
        final pf = query['pf'];
        return (pf == null || pf.isEmpty)
            ? null
            : DeepLinkDestination(DeepLinkTo.invitacion, null, pf);
      default:
        return null;
    }
  }
}
