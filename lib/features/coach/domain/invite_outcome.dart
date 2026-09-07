import 'trainer_link.dart';
import 'trainer_link_status.dart';

/// Qué se puede hacer cuando un alumno abre un link de invitación.
///
/// Es una función PURA sobre (invitación, vínculo actual). No toca Firestore,
/// no navega, no muestra nada: sólo decide. Eso es a propósito — los cinco
/// casos del flujo de invitación son reglas de producto, y tenerlas mezcladas
/// con la UI significa que la única forma de verificarlas es abrir la app cinco
/// veces con cinco cuentas distintas.
///
/// La regla que las ordena a todas ya estaba escrita en
/// `trainer_contact_cta_stub.dart`: **un alumno se vincula con UN PF a la vez**.
/// De ahí sale que una invitación de otro PF no pueda aplicarse sola.
sealed class InviteOutcome {
  const InviteOutcome();
}

/// No tiene PF: la invitación se puede aplicar directo.
class InvitePuedeVincular extends InviteOutcome {
  const InvitePuedeVincular(this.trainerId);

  final String trainerId;
}

/// Ya tiene una solicitud pendiente con ESE mismo PF.
///
/// Distinto de [InviteYaVinculado] porque lo que hay que decirle es distinto:
/// no está vinculado todavía, está esperando que el PF acepte. Prometerle que
/// ya está sería mentirle sobre el estado de su propia cuenta.
class InviteYaSolicitado extends InviteOutcome {
  const InviteYaSolicitado(this.trainerId);

  final String trainerId;
}

/// Ya está vinculado con ESE mismo PF. Caso D: no se duplica nada.
class InviteYaVinculado extends InviteOutcome {
  const InviteYaVinculado(this.trainerId);

  final String trainerId;
}

/// Caso E: está vinculado con OTRO PF.
///
/// No se resuelve solo. Cambiar de entrenador es una decisión del alumno, y
/// aplicarla porque abrió un link —que le pudo llegar reenviado, o que pudo
/// tocar sin querer— sería tomarla por él.
class InviteRequiereDesvincular extends InviteOutcome {
  const InviteRequiereDesvincular({
    required this.nuevoTrainerId,
    required this.vinculoActual,
  });

  final String nuevoTrainerId;

  /// El vínculo que habría que terminar primero.
  final TrainerLink vinculoActual;
}

/// El entrenador abrió un link generado por otra cuenta.
///
/// No se puede aplicar porque las invitaciones crean vínculos desde el lado
/// del alumno. Conservar el motivo permite que la presentación explique el
/// rechazo en vez de hacer parecer que el deep link falló.
class InviteSoloParaAlumnos extends InviteOutcome {
  const InviteSoloParaAlumnos();
}

/// El entrenador abrió el link que él mismo comparte con sus alumnos.
///
/// Es distinto de una invitación inválida: la captura funcionó y confirmarlo
/// evita que una prueba legítima del link termine pareciendo un fallo.
class InviteLinkPropio extends InviteOutcome {
  const InviteLinkPropio();
}

/// La invitación no aplica y no hay nada que preguntar.
///
/// Se reserva para entradas sin entrenador. No hay una acción explícita que la
/// UI pueda atribuir a la persona, así que tampoco hay un mensaje honesto para
/// mostrarle.
class InviteNoAplica extends InviteOutcome {
  const InviteNoAplica();
}

/// Resuelve qué hacer con la invitación de [inviteTrainerId] para [athleteId].
///
/// [vinculoActual] es el vínculo NO terminado del alumno —el que devuelve
/// `currentAthleteLinkAnyStatusProvider`— o `null` si no tiene ninguno.
InviteOutcome resolveInvite({
  required String inviteTrainerId,
  required String athleteId,
  required TrainerLink? vinculoActual,
}) {
  if (inviteTrainerId.isEmpty) return const InviteNoAplica();
  if (inviteTrainerId == athleteId) return const InviteLinkPropio();
  if (vinculoActual == null) {
    return InvitePuedeVincular(inviteTrainerId);
  }
  if (vinculoActual.trainerId == inviteTrainerId) {
    // Mismo PF: nunca se crea un segundo vínculo. Lo único que cambia es qué
    // se le cuenta, según haya aceptado ya o no.
    return vinculoActual.status == TrainerLinkStatus.pending
        ? InviteYaSolicitado(inviteTrainerId)
        : InviteYaVinculado(inviteTrainerId);
  }
  return InviteRequiereDesvincular(
    nuevoTrainerId: inviteTrainerId,
    vinculoActual: vinculoActual,
  );
}

/// Resuelve una invitación capturada mientras hay una sesión de entrenador.
InviteOutcome resolveTrainerInvite({
  required String inviteTrainerId,
  required String trainerId,
}) {
  if (inviteTrainerId.isEmpty) return const InviteNoAplica();
  return inviteTrainerId == trainerId
      ? const InviteLinkPropio()
      : const InviteSoloParaAlumnos();
}
