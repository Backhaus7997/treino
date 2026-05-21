// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'check_in.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$CheckInImpl _$$CheckInImplFromJson(Map<String, dynamic> json) =>
    _$CheckInImpl(
      uid: json['uid'] as String,
      date: json['date'] as String,
      checkedInAt:
          const TimestampConverter().fromJson(json['checkedInAt'] as Timestamp),
      gymId: json['gymId'] as String?,
      gymName: json['gymName'] as String?,
    );

Map<String, dynamic> _$$CheckInImplToJson(_$CheckInImpl instance) =>
    <String, dynamic>{
      'uid': instance.uid,
      'date': instance.date,
      'checkedInAt': const TimestampConverter().toJson(instance.checkedInAt),
      'gymId': instance.gymId,
      'gymName': instance.gymName,
    };
