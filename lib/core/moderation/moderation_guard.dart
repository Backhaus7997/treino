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

  // Esta excepcion NO carga el texto que ve el usuario.
  //
  // La app tiene tres locales (`en`, `es`, `es_AR`) y el copy vive en
  // `lib/l10n/*.arb`, bajo `moderationBlockedMessage`. Una capa de datos que
  // devuelve una cadena en castellano rioplatense obliga a traducirla desde
  // donde no hay contexto, o —peor— la deja sin traducir y nadie lo nota
  // hasta que un usuario en ingles ve media pantalla en espaniol.

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

  static final RegExp _diaSolo = RegExp(r'^days\[(\d+)\]\.name$');
  static final RegExp _diaYSlot =
      RegExp(r'^days\[(\d+)\]\.slots\[(\d+)\]\.notes$');

  /// Traduce el `campo` crudo de [ModerationBlockedException] (p.ej.
  /// `'days[3].slots[7].notes'`) a una ubicacion legible para un humano
  /// (p.ej. "Dia 4, ejercicio 8"). `null` si [campo] no tiene una ubicacion
  /// indexada que mostrar — top-level (`name`, `split`, `summary`) u otro
  /// campo fuera de rutinas (`displayName`, `trainerBio`).
  ///
  /// El `campo` crudo usa indices de base 0 (para correlacionar con el
  /// registro del servidor, ver el dartdoc de `_ensureRoutineTextIsClean` en
  /// `routine_repository.dart`); los que ve el usuario empiezan en 1. Esta
  /// funcion es la UNICA que lo traduce — antes de esto nada parseaba
  /// `campo` en absoluto, asi que en una rutina de 5 dias x 8 slots el PF
  /// tenia que adivinar cual de 40 notas era.
  static String? ubicacionLegible(String campo) {
    final soloDia = _diaSolo.firstMatch(campo);
    if (soloDia != null) {
      final dia = int.parse(soloDia.group(1)!) + 1;
      return 'Día $dia'; // i18n: Fase 11
    }
    final diaYSlot = _diaYSlot.firstMatch(campo);
    if (diaYSlot != null) {
      final dia = int.parse(diaYSlot.group(1)!) + 1;
      final ejercicio = int.parse(diaYSlot.group(2)!) + 1;
      return 'Día $dia, ejercicio $ejercicio'; // i18n: Fase 11
    }
    return null;
  }
}
