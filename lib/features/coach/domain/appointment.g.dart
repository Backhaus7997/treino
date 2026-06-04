// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'appointment.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$CancellationEntryImpl _$$CancellationEntryImplFromJson(
        Map<String, dynamic> json) =>
    _$CancellationEntryImpl(
      byUid: json['byUid'] as String,
      atMs: (json['atMs'] as num).toInt(),
      reason: json['reason'] as String?,
    );

Map<String, dynamic> _$$CancellationEntryImplToJson(
        _$CancellationEntryImpl instance) =>
    <String, dynamic>{
      'byUid': instance.byUid,
      'atMs': instance.atMs,
      'reason': instance.reason,
    };

_$AppointmentImpl _$$AppointmentImplFromJson(Map<String, dynamic> json) =>
    _$AppointmentImpl(
      id: json['id'] as String,
      trainerId: json['trainerId'] as String,
      athleteId: json['athleteId'] as String,
      athleteDisplayName: json['athleteDisplayName'] as String,
      startsAt:
          const TimestampConverter().fromJson(json['startsAt'] as Timestamp),
      durationMin: (json['durationMin'] as num).toInt(),
      status: $enumDecode(_$AppointmentStatusEnumMap, json['status']),
      cancelledAt: _$JsonConverterFromJson<Timestamp, DateTime>(
          json['cancelledAt'], const TimestampConverter().fromJson),
      cancelledBy: json['cancelledBy'] as String?,
      cancellationLog: (json['cancellationLog'] as List<dynamic>?)
              ?.map(
                  (e) => CancellationEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      noteBefore: json['noteBefore'] as String?,
      noteAfter: json['noteAfter'] as String?,
      recurringId: json['recurringId'] as String?,
    );

Map<String, dynamic> _$$AppointmentImplToJson(_$AppointmentImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'trainerId': instance.trainerId,
      'athleteId': instance.athleteId,
      'athleteDisplayName': instance.athleteDisplayName,
      'startsAt': const TimestampConverter().toJson(instance.startsAt),
      'durationMin': instance.durationMin,
      'status': _$AppointmentStatusEnumMap[instance.status]!,
      'cancelledAt': _$JsonConverterToJson<Timestamp, DateTime>(
          instance.cancelledAt, const TimestampConverter().toJson),
      'cancelledBy': instance.cancelledBy,
      'cancellationLog':
          instance.cancellationLog.map((e) => e.toJson()).toList(),
      'noteBefore': instance.noteBefore,
      'noteAfter': instance.noteAfter,
      'recurringId': instance.recurringId,
    };

const _$AppointmentStatusEnumMap = {
  AppointmentStatus.confirmed: 'confirmed',
  AppointmentStatus.cancelled: 'cancelled',
};

Value? _$JsonConverterFromJson<Json, Value>(
  Object? json,
  Value? Function(Json json) fromJson,
) =>
    json == null ? null : fromJson(json as Json);

Json? _$JsonConverterToJson<Json, Value>(
  Value? value,
  Json? Function(Value value) toJson,
) =>
    value == null ? null : toJson(value);
