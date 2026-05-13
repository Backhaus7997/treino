// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'routine_day.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$RoutineDayImpl _$$RoutineDayImplFromJson(Map<String, dynamic> json) =>
    _$RoutineDayImpl(
      dayNumber: (json['dayNumber'] as num).toInt(),
      name: json['name'] as String,
      slots: (json['slots'] as List<dynamic>)
          .map((e) => RoutineSlot.fromJson(e as Map<String, dynamic>))
          .toList(),
      estimatedMinutes: (json['estimatedMinutes'] as num?)?.toInt(),
    );

Map<String, dynamic> _$$RoutineDayImplToJson(_$RoutineDayImpl instance) =>
    <String, dynamic>{
      'dayNumber': instance.dayNumber,
      'name': instance.name,
      'slots': instance.slots.map((e) => e.toJson()).toList(),
      'estimatedMinutes': instance.estimatedMinutes,
    };
