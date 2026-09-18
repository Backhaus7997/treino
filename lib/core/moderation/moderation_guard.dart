import 'moderation_filter.dart';

/// El texto que se intento publicar tiene un termino vetado.
///
/// El mensaje es generico A PROPOSITO: no nombra el termino ni el motivo.
/// Decirle al usuario que palabra salto convierte al filtro en un oraculo —
/// quien quiera evadirlo prueba variantes hasta que el mensaje deja de
/// aparecer, y el mensaje le confirma exactamente cuando lo logro.
class ModerationBlockedException implements Exception {
  const ModerationBlockedException(this.campo);

  /// Que campo se rechazo. Para logs internos y para que la UI sepa donde
  /// pintar el error, NUNCA para mostrarle al usuario que palabra fue.
  final String campo;

  /// Lo que ve el usuario.
  String get mensaje =>
      'Ese texto no se puede publicar porque incumple las Normas de '
      'Comunidad. Revisalo y volvé a intentar.';

  @override
  String toString() => 'ModerationBlockedException($campo)';
}

/// Punto de control del filtrado de terminos vetados en el cliente.
///
/// ## Por que en el repositorio y no en la pantalla
///
/// La pantalla es donde el usuario ve el error, pero el repositorio es el
/// cuello de botella: la proxima pantalla que publique un post no puede
/// olvidarse de filtrar si el filtro vive del lado de la escritura. Es ademas
/// el patron que estos repos ya usan —`ChatRepository.sendMessage` lanza
/// `ArgumentError` cuando el mensaje no tiene ni texto ni adjunto.
///
/// ## Esta capa no es la ultima
///
/// El cliente se saltea con el SDK directo. El espejo de
/// `functions/src/moderation/` pone en cuarentena lo que paso igual. Las dos
/// hacen falta: esta es la que satisface la Guideline 1.2 —el contenido no
/// llega a postearse— y la otra es la que de verdad no se puede evadir.
abstract final class ModerationGuard {
  const ModerationGuard._();

  /// Lanza [ModerationBlockedException] si [texto] tiene un termino de
  /// severidad `block`.
  ///
  /// `null` y vacio pasan: "no escribio nada" no es "escribio algo vetado", y
  /// los campos opcionales (el comentario de una resena, el texto de un post
  /// que es solo una foto) llegan vacios todo el tiempo.
  ///
  /// La severidad `review` NO frena la escritura a proposito: pasa, y el
  /// reporte automatico lo crea la Cloud Function del slice 3, que es la que
  /// puede escribir en la cola de moderacion. Frenarla aca convertiria un
  /// "esto amerita que alguien lo mire" en un "no podes publicar", que es una
  /// decision de producto distinta y mas cara.
  static void ensure(String? texto, {required String campo}) {
    if (texto == null || texto.trim().isEmpty) return;
    if (ModerationFilter.check(texto) == ModerationVerdict.block) {
      throw ModerationBlockedException(campo);
    }
  }
}
