// Terminar un vínculo desde el lado del PF, liberando de paso los turnos
// futuros con ese alumno (#1792).
//
// Terminar sólo toca `trainer_links`: los turnos del par quedaban `confirmed`
// ocupando horario. Decisión (conservadora): al terminar se CANCELAN los turnos
// futuros del par por el camino de siempre (el alumno recibe las notificaciones
// de siempre). No se borra nada: quedan `cancelled` con su `cancellationLog`.
//
// Primero los turnos, después el vínculo: si fuera al revés y la cancelación
// fallara, el vínculo quedaría terminado con turnos colgados. Así un fallo deja
// TODO como estaba (vínculo activo, reintentable).
//
// No cubre el vínculo que termina el ALUMNO: el atleta no puede cancelar a menos
// de 24h con las reglas actuales, eso necesita una Cloud Function.
library;

import '../data/appointment_repository.dart';
import '../data/trainer_link_repository.dart';
import '../domain/trainer_link.dart';

/// Motivo que queda en el `cancellationLog` de cada turno cancelado por esto.
const kMotivoTurnoPorFinDeVinculo = 'Vínculo terminado por el entrenador.';

/// La cancelación de los turnos futuros falló: el vínculo NO se terminó.
class TurnosFuturosSinCancelar implements Exception {
  const TurnosFuturosSinCancelar(this.causa);

  final Object causa;
}

/// Cuántos turnos futuros confirmados tiene el PF con [link]`.athleteId`, o
/// `null` si no se pudo contar. `null` NO es cero: «no sé» y «ninguno» se le
/// avisan distinto al PF.
Future<int?> contarTurnosFuturos(
  AppointmentRepository appointments,
  TrainerLink link,
) async {
  try {
    final futuros = await appointments.listFutureConfirmedForPair(
      trainerId: link.trainerId,
      athleteId: link.athleteId,
    );
    return futuros.length;
  } catch (_) {
    return null;
  }
}

/// Cancela los turnos futuros del par y termina el vínculo, en ese orden.
/// Devuelve cuántos turnos canceló.
///
/// Si la cancelación falla lanza [TurnosFuturosSinCancelar] y NO toca el
/// vínculo. Si `terminate` falla, la excepción sale tal cual (los turnos ya
/// están cancelados; reintentar sólo termina el vínculo).
Future<int> terminarVinculoLiberandoTurnos({
  required TrainerLinkRepository links,
  required AppointmentRepository appointments,
  required TrainerLink link,
  String reason = 'trainer-terminated',
}) async {
  final int cancelados;
  try {
    cancelados = await appointments.cancelFutureForPair(
      trainerId: link.trainerId,
      athleteId: link.athleteId,
      actorUid: link.trainerId,
      reason: kMotivoTurnoPorFinDeVinculo,
    );
  } catch (e) {
    throw TurnosFuturosSinCancelar(e);
  }
  await links.terminate(link.id, reason: reason);
  return cancelados;
}
