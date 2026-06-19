import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:json_annotation/json_annotation.dart';

class TimestampConverter implements JsonConverter<DateTime, Timestamp> {
  const TimestampConverter();

  @override
  DateTime fromJson(Timestamp json) => json.toDate().toUtc();

  @override
  Timestamp toJson(DateTime object) => Timestamp.fromDate(object);
}

class TimestampMapConverter
    implements JsonConverter<Map<String, DateTime>, Map<String, Object?>> {
  const TimestampMapConverter();

  @override
  Map<String, DateTime> fromJson(Map<String, Object?> json) {
    return json.map(
      (uid, ts) => MapEntry(uid, (ts as Timestamp).toDate().toUtc()),
    );
  }

  @override
  Map<String, Object?> toJson(Map<String, DateTime> object) {
    return object.map(
      (uid, dt) => MapEntry(uid, Timestamp.fromDate(dt)),
    );
  }
}
