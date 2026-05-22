/// Exceptions thrown by the Coach Agenda data layer.
///
/// Each exception maps to a locked Rioplatense user message in
/// `agenda_strings.dart` (PR2 — ADR-4).

/// Thrown by `AppointmentRepository.book` when the slot is already taken by
/// a confirmed appointment. SCENARIO-490.
class SlotAlreadyTakenException implements Exception {
  const SlotAlreadyTakenException(this.appointmentId);
  final String appointmentId;

  @override
  String toString() =>
      'SlotAlreadyTakenException(appointmentId=$appointmentId)';
}

/// Thrown by `AppointmentRepository.cancel` when called less than 24 hours
/// before `startsAt`. SCENARIO-493 / REQ-COACH-AGENDA-007.
class CancellationTooLateException implements Exception {
  const CancellationTooLateException(this.appointmentId);
  final String appointmentId;

  @override
  String toString() =>
      'CancellationTooLateException(appointmentId=$appointmentId)';
}

/// Thrown by `AppointmentRepository.book` when `startsAt` is more than 28
/// days from now. SCENARIO-496 / REQ-COACH-AGENDA-009.
class BookingTooFarAheadException implements Exception {
  const BookingTooFarAheadException();

  @override
  String toString() => 'BookingTooFarAheadException()';
}
