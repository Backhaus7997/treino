// ignore: unused_import — Timestamp is used by the generated payment.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';

part 'payment.freezed.dart';
part 'payment.g.dart';

enum PaymentStatus {
  @JsonValue('pending')
  pending,
  @JsonValue('paid')
  paid,
}

/// A payment record created by the trainer against an athlete.
///
/// Stored in `payments/{autoId}`.
@freezed
class Payment with _$Payment {
  const factory Payment({
    required String id,
    required String trainerId,
    required String athleteId,
    required int amountArs,
    required String concept,
    required PaymentStatus status,
    String? periodKey,
    @TimestampConverter() required DateTime createdAt,
    @TimestampConverter() DateTime? paidAt,
    @TimestampConverter() DateTime? dueAt,
    @TimestampConverter() DateTime? lastOverdueNotifiedAt,
  }) = _Payment;

  factory Payment.fromJson(Map<String, Object?> json) =>
      _$PaymentFromJson(json);
}
