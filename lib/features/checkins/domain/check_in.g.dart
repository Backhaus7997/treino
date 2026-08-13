// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'check_in.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$CheckInImpl _$$CheckInImplFromJson(Map<String, dynamic> json) =>
    _$CheckInImpl(
      date: json['date'] as String,
      feeling: $enumDecode(_$CheckInFeelingEnumMap, json['feeling']),
      hasPain: json['hasPain'] as bool? ?? false,
      painAreas: json['painAreas'] == null
          ? const <MuscleGroup>[]
          : const MuscleGroupKeysConverter()
              .fromJson(json['painAreas'] as List),
      note: json['note'] as String?,
      recordedAt:
          const TimestampConverter().fromJson(json['recordedAt'] as Timestamp),
      sessionId: json['sessionId'] as String?,
    );

Map<String, dynamic> _$$CheckInImplToJson(_$CheckInImpl instance) =>
    <String, dynamic>{
      'date': instance.date,
      'feeling': _$CheckInFeelingEnumMap[instance.feeling]!,
      'hasPain': instance.hasPain,
      'painAreas': const MuscleGroupKeysConverter().toJson(instance.painAreas),
      'note': instance.note,
      'recordedAt': const TimestampConverter().toJson(instance.recordedAt),
      'sessionId': instance.sessionId,
    };

const _$CheckInFeelingEnumMap = {
  CheckInFeeling.muyMal: 'very_bad',
  CheckInFeeling.mal: 'bad',
  CheckInFeeling.normal: 'neutral',
  CheckInFeeling.bien: 'good',
  CheckInFeeling.muyBien: 'great',
};
