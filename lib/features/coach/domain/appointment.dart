// ignore: unused_import — Timestamp is used by the generated appointment.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';

part 'appointment.freezed.dart';
part 'appointment.g.dart';

/// Wire values for [AppointmentStatus]. SCENARIO-483.
enum AppointmentStatus {
  @JsonValue('confirmed')
  confirmed,

  @JsonValue('cancelled')
  cancelled,
}

/// Asistencia que el PF marca sobre una sesión que ya empezó (#1492).
///
/// No es un [AppointmentStatus] a propósito: las queries de la agenda y el
/// cobro filtran `status == 'confirmed'`, así que un estado "ausente" sacaba
/// la sesión de la agenda de las dos partes y la volvía incobrable. `null` en
/// [Appointment.attendance] es "se dio", que es lo que el dashboard ya derivaba
/// de `confirmed` + ya terminó.
enum AppointmentAttendance {
  @JsonValue('absent')
  absent('absent');

  const AppointmentAttendance(this.wire);

  /// El valor que se guarda en Firestore (lo acota `firestore.rules`).
  final String wire;
}

/// A single cancellation log entry — immutable audit trail. ADR-1.
@freezed
class CancellationEntry with _$CancellationEntry {
  const factory CancellationEntry({
    required String byUid,
    required int atMs,
    String? reason,
  }) = _CancellationEntry;

  factory CancellationEntry.fromJson(Map<String, Object?> json) =>
      _$CancellationEntryFromJson(json);
}

/// Booking record stored at `appointments/{trainerId}_{startsAtMs}`.
///
/// The deterministic doc ID is `'${trainerId}_${startsAt.millisecondsSinceEpoch}'`.
/// All [DateTime] fields are UTC. ADR-5, ADR-7.
@freezed
class Appointment with _$Appointment {
  const Appointment._();

  const factory Appointment({
    required String id,
    required String trainerId,
    required String athleteId,
    required String athleteDisplayName,
    @TimestampConverter() required DateTime startsAt,
    required int durationMin,
    required AppointmentStatus status,
    @TimestampConverter() DateTime? cancelledAt,
    String? cancelledBy,
    @Default([]) List<CancellationEntry> cancellationLog,
    String? noteBefore,
    String? noteAfter,
    // non-null → this session belongs to a recurring series created in one
    // shot by the trainer. All occurrences of the same series share this id,
    // enabling "cancel all future" without a separate series document.
    String? recurringId,
    // Agenda→cobro bridge (Slice 2a, per-turno granularity). null → not
    // billed yet; non-null → the id of the `Payment` doc that covers this
    // session. Set exactly once via AppointmentRepository.billAppointment /
    // markBilled — never cleared client-side (see firestore.rules set-once
    // guard on this field).
    String? paymentId,
    // #1492 — null = la sesión se dio; [AppointmentAttendance.absent] = el
    // alumno faltó. Lo escribe sólo el PF (AppointmentRepository.setAttendance,
    // Path 2 de firestore.rules).
    //
    // `includeIfNull: false` NO es estética: `createByTrainer` escribe
    // `toJson()` entero, y las reglas desplegadas ANTES de #1492 no tienen la
    // clave en su allowlist. Omitirla cuando es null deja que esta versión de
    // la app siga agendando aunque las reglas nuevas todavía no estén arriba.
    // ignore: invalid_annotation_target
    @JsonKey(
      includeIfNull: false,
      unknownEnumValue: JsonKey.nullForUndefinedEnumValue,
    )
    AppointmentAttendance? attendance,
  }) = _Appointment;

  factory Appointment.fromJson(Map<String, Object?> json) =>
      _$AppointmentFromJson(json);

  /// Creates a new [Appointment] with a deterministic doc ID. ADR-7: asserts
  /// minute precision on [startsAt] (second == 0 && millisecond == 0 &&
  /// microsecond == 0).
  factory Appointment.create({
    required String trainerId,
    required String athleteId,
    required String athleteDisplayName,
    required DateTime startsAt,
    required int durationMin,
    AppointmentStatus status = AppointmentStatus.confirmed,
  }) {
    assert(
      startsAt.second == 0 &&
          startsAt.millisecond == 0 &&
          startsAt.microsecond == 0,
      'ADR-7: startsAt must have second == 0, millisecond == 0, microsecond == 0',
    );
    return Appointment(
      id: '${trainerId}_${startsAt.millisecondsSinceEpoch}',
      trainerId: trainerId,
      athleteId: athleteId,
      athleteDisplayName: athleteDisplayName,
      startsAt: startsAt,
      durationMin: durationMin,
      status: status,
    );
  }
}
