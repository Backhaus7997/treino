// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'athlete_note.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$AthleteNoteImpl _$$AthleteNoteImplFromJson(Map<String, dynamic> json) =>
    _$AthleteNoteImpl(
      trainerId: json['trainerId'] as String,
      athleteId: json['athleteId'] as String,
      note: json['note'] as String,
      updatedAt:
          const TimestampConverter().fromJson(json['updatedAt'] as Timestamp),
    );

Map<String, dynamic> _$$AthleteNoteImplToJson(_$AthleteNoteImpl instance) =>
    <String, dynamic>{
      'trainerId': instance.trainerId,
      'athleteId': instance.athleteId,
      'note': instance.note,
      'updatedAt': const TimestampConverter().toJson(instance.updatedAt),
    };
