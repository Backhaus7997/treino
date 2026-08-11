// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'exercise_feedback.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ExerciseFeedbackImpl _$$ExerciseFeedbackImplFromJson(
        Map<String, dynamic> json) =>
    _$ExerciseFeedbackImpl(
      id: json['id'] as String,
      exerciseId: json['exerciseId'] as String,
      exerciseName: json['exerciseName'] as String,
      slotIndex: (json['slotIndex'] as num).toInt(),
      setNumber: (json['setNumber'] as num?)?.toInt(),
      kind: $enumDecode(_$ExerciseFeedbackKindEnumMap, json['kind']),
      text: json['text'] as String?,
      photoUrl: json['photoUrl'] as String?,
      photoPath: json['photoPath'] as String?,
      createdAt:
          const TimestampConverter().fromJson(json['createdAt'] as Timestamp),
    );

Map<String, dynamic> _$$ExerciseFeedbackImplToJson(
        _$ExerciseFeedbackImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'exerciseId': instance.exerciseId,
      'exerciseName': instance.exerciseName,
      'slotIndex': instance.slotIndex,
      'setNumber': instance.setNumber,
      'kind': _$ExerciseFeedbackKindEnumMap[instance.kind]!,
      'text': instance.text,
      'photoUrl': instance.photoUrl,
      'photoPath': instance.photoPath,
      'createdAt': const TimestampConverter().toJson(instance.createdAt),
    };

const _$ExerciseFeedbackKindEnumMap = {
  ExerciseFeedbackKind.comment: 'comment',
  ExerciseFeedbackKind.discomfort: 'discomfort',
};
