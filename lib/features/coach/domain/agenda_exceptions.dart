/// Exceptions thrown by the Coach Agenda data layer.
///
/// Each exception maps to a locked Rioplatense user message in
/// `agenda_strings.dart` (PR2 — ADR-4).
library;

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

/// Thrown by `AppointmentRepository.book` when `startsAt` is at or before
/// "now" (wall-clock, ADR-7) — a session can't be booked in the past. Mirrors
/// the UI-side guard in new_session_sheet.dart. QA-COA-003.
class BookingInThePastException implements Exception {
  const BookingInThePastException();

  @override
  String toString() => 'BookingInThePastException()';
}

/// Thrown by `AppointmentRepository.billAppointment` when the appointment
/// already has a non-null `paymentId` — guards against re-cobro from a
/// double-submit or a stale/reopened detail dialog (Slice 2a, money-critical).
class AppointmentAlreadyBilledException implements Exception {
  const AppointmentAlreadyBilledException(this.appointmentId);
  final String appointmentId;

  @override
  String toString() =>
      'AppointmentAlreadyBilledException(appointmentId=$appointmentId)';
}

/// Thrown by `AppointmentRepository.billAppointment` when the appointment
/// doc no longer exists at commit time (Slice 2a).
class AppointmentNotFoundException implements Exception {
  const AppointmentNotFoundException(this.appointmentId);
  final String appointmentId;

  @override
  String toString() =>
      'AppointmentNotFoundException(appointmentId=$appointmentId)';
}

/// Thrown by `AppointmentRepository.billAppointment` when the appointment's
/// live status isn't `confirmed` anymore (e.g. cancelled concurrently in
/// another tab) — a cancelled session must never be billed (Slice 2a).
class AppointmentNotConfirmedException implements Exception {
  const AppointmentNotConfirmedException(this.appointmentId);
  final String appointmentId;

  @override
  String toString() =>
      'AppointmentNotConfirmedException(appointmentId=$appointmentId)';
}

/// Thrown by `AppointmentRepository.billAppointments` (Slice 2b, batch
/// billing) when one of the appointments in the batch does NOT belong to the
/// same athlete+trainer as the [Payment] being created for the whole batch.
///
/// A single Payment always has exactly one `athleteId` (design decision,
/// Slice 2b) — the UI locks the selection to one athlete once the first
/// turno is picked, but this exception is the server-authoritative guard: it
/// re-validates every appointment's LIVE doc data against the batch's
/// payment inside the same transaction, so a stale client-side selection (or
/// any caller that bypasses the UI lock) can never mix athletes into one
/// Payment.
class AppointmentAthleteMismatchException implements Exception {
  const AppointmentAthleteMismatchException(this.appointmentId);
  final String appointmentId;

  @override
  String toString() =>
      'AppointmentAthleteMismatchException(appointmentId=$appointmentId)';
}
