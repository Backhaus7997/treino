/// UI copy for the Coach Agenda feature (es-AR / Rioplatense). ADR-4.
///
/// All visible strings for the athlete booking flow and appointment
/// management live here. No inline literals in widget code per project
/// convention.
abstract final class AgendaStrings {
  // ── Entry point (athlete_coach_view.dart) ─────────────────────────────────
  static const agendaButtonLabel = 'VER AGENDA DEL PF';

  // ── AthleteAgendaScreen ───────────────────────────────────────────────────
  static const agendaScreenTitle = 'Agenda';
  static const emptyAvailability = 'Tu PF todavía no configuró horarios.';

  // ── Booking confirmation dialog ───────────────────────────────────────────
  static const bookingConfirmTitle = 'Confirmar reserva';
  static String bookingConfirmBody(DateTime t) =>
      '¿Confirmar reserva el ${formatDate(t)} a las ${formatTime(t)}?';
  static const bookingConfirmCta = 'Confirmar';
  static const bookingCancel = 'Cancelar';
  static const bookingSuccess = 'Reserva confirmada.';
  static const bookingRaceError =
      'Ese horario fue reservado justo ahora. Probá con otro.';

  // ── Cancellation dialog ───────────────────────────────────────────────────
  static const cancellationConfirmTitle = 'Cancelar reserva';
  static const cancellationConfirmBody = '¿Cancelar esta reserva?';
  static const cancellationConfirmCta = 'Sí, cancelar';
  static const cancellationKeep = 'No, mantener';
  static const cancellationSuccess = 'Reserva cancelada.';
  static const cancellationTooLate =
      'No podés cancelar con menos de 24h de anticipación.';

  // ── Appointments list section headings ────────────────────────────────────
  static const upcomingAppointmentsHeading = 'TUS PRÓXIMAS RESERVAS';
  static const pastAppointmentsHeading = 'TURNOS PASADOS';

  // ── Generic error ─────────────────────────────────────────────────────────
  static const genericError = 'Hubo un problema. Intentá de nuevo.';

  // ── Trainer UI strings (PR3) ──────────────────────────────────────────────
  static const trainerEmptyAvailability =
      'Todavía no configuraste tus horarios de trabajo. '
      'Agregá uno para que tus alumnos puedan reservar.';
  static const configureHoursCta = 'CONFIGURAR HORARIOS';
  static const myWorkingHoursHeading = 'MIS HORARIOS DE TRABAJO';
  static const addRuleCta = 'AGREGAR HORARIO';
  static const blockDayCta = 'BLOQUEAR UN DÍA';
  static const editorTitle = 'Mis horarios';
  static const ruleDeleteConfirm =
      '¿Borrar este horario? Las reservas existentes se mantienen.';
  static const bookingCancelledByCoach = 'Reserva cancelada por el entrenador.';
  static const slotFreeLabel = 'Disponible';
  static const slotBlockedLabel = 'Bloqueado';

  static String slotBookedByLabel(String athleteName) =>
      'Reservado por $athleteName';

  /// ISO weekday → display label (1=Monday … 7=Sunday).
  static const Map<int, String> dayOfWeekLabels = {
    1: 'Lunes',
    2: 'Martes',
    3: 'Miércoles',
    4: 'Jueves',
    5: 'Viernes',
    6: 'Sábado',
    7: 'Domingo',
  };

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Formats a [DateTime] as `dd/MM/yyyy` in local time.
  static String formatDate(DateTime dt) {
    final d = dt.toLocal();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }

  /// Formats a [DateTime] as `HH:mm` in local time.
  static String formatTime(DateTime dt) {
    final d = dt.toLocal();
    final hh = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$hh:$min';
  }
}
