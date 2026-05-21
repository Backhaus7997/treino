// ignore: unused_import — Timestamp is used by the generated check_in.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';

part 'check_in.freezed.dart';
part 'check_in.g.dart';

@freezed
class CheckIn with _$CheckIn {
  const factory CheckIn({
    required String uid,

    /// 'YYYY-MM-DD' in user local time. Also the Firestore doc id → natural dedup.
    required String date,
    @TimestampConverter() required DateTime checkedInAt,
    String? gymId,
    String? gymName,
  }) = _CheckIn;

  factory CheckIn.fromJson(Map<String, Object?> json) =>
      _$CheckInFromJson(json);

  /// Returns 'YYYY-MM-DD' for the given LOCAL date. Zero-pads month/day/year.
  static String dateKey(DateTime localDate) {
    final y = localDate.year.toString().padLeft(4, '0');
    final m = localDate.month.toString().padLeft(2, '0');
    final d = localDate.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
