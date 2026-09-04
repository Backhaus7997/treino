/// Un destino fino dentro de la app o del Coach Hub, codificado en el `to`
/// (y opcionalmente `id`) que los mails transaccionales agregan al CTA del
/// entrenador — ver `functions/src/mail/templates.ts` (`trainerEntry`).
///
/// Esto es SOLO el parsing. Que hacer con cada valor —a qué RUTA mapea— es
/// decisión de cada router: mobile y Coach Hub web tienen paths distintos
/// para el mismo destino (`/coach/athlete/:id` vs `/alumnos/:id`), así que
/// compartir esa parte sería forzar una coincidencia que no existe. Cada
/// router tiene su propio switch de acá para adelante.
enum DeepLinkTo { facturacion, agenda, solicitudes, alumno }

class DeepLinkDestination {
  const DeepLinkDestination(this.to, [this.athleteId]);

  final DeepLinkTo to;

  /// Solo tiene valor cuando `to == DeepLinkTo.alumno`. El constructor no lo
  /// exige porque Dart no tiene unions taggeados nativos, pero
  /// [fromQuery] SÍ hace cumplir el invariante: nunca devuelve un
  /// `DeepLinkTo.alumno` sin `athleteId`.
  final String? athleteId;

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
      default:
        return null;
    }
  }
}
