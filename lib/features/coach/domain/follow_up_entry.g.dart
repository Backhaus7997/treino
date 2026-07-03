// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'follow_up_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$FollowUpEntryImpl _$$FollowUpEntryImplFromJson(Map<String, dynamic> json) =>
    _$FollowUpEntryImpl(
      id: json['id'] as String,
      trainerId: json['trainerId'] as String,
      athleteId: json['athleteId'] as String,
      text: json['text'] as String,
      tag: $enumDecode(_$FollowUpTagEnumMap, json['tag']),
      recordedAt:
          const TimestampConverter().fromJson(json['recordedAt'] as Timestamp),
    );

Map<String, dynamic> _$$FollowUpEntryImplToJson(_$FollowUpEntryImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'trainerId': instance.trainerId,
      'athleteId': instance.athleteId,
      'text': instance.text,
      'tag': _$FollowUpTagEnumMap[instance.tag]!,
      'recordedAt': const TimestampConverter().toJson(instance.recordedAt),
    };

const _$FollowUpTagEnumMap = {
  FollowUpTag.general: 'general',
  FollowUpTag.entrenamiento: 'entrenamiento',
  FollowUpTag.nutricion: 'nutricion',
  FollowUpTag.molestia: 'molestia',
  FollowUpTag.motivacion: 'motivacion',
};
