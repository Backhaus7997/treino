// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trainer_location.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$TrainerLocationImpl _$$TrainerLocationImplFromJson(
        Map<String, dynamic> json) =>
    _$TrainerLocationImpl(
      id: json['id'] as String,
      type: $enumDecode(_$TrainerLocationTypeEnumMap, json['type']),
      gymId: json['gymId'] as String?,
      customLabel: json['customLabel'] as String?,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      geohash: json['geohash'] as String,
    );

Map<String, dynamic> _$$TrainerLocationImplToJson(
        _$TrainerLocationImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': _$TrainerLocationTypeEnumMap[instance.type]!,
      'gymId': instance.gymId,
      'customLabel': instance.customLabel,
      'lat': instance.lat,
      'lng': instance.lng,
      'geohash': instance.geohash,
    };

const _$TrainerLocationTypeEnumMap = {
  TrainerLocationType.gym: 'gym',
  TrainerLocationType.custom: 'custom',
};
