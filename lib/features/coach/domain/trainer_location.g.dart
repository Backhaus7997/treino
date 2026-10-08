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
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      geohash: json['geohash'] as String?,
      placeId: json['placeId'] as String?,
      coordsFetchedAt: _$JsonConverterFromJson<Timestamp, DateTime>(
          json['coordsFetchedAt'], const TimestampConverter().fromJson),
      stale: json['stale'] as bool?,
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
      'placeId': instance.placeId,
      'coordsFetchedAt': _$JsonConverterToJson<Timestamp, DateTime>(
          instance.coordsFetchedAt, const TimestampConverter().toJson),
      'stale': instance.stale,
    };

const _$TrainerLocationTypeEnumMap = {
  TrainerLocationType.gym: 'gym',
  TrainerLocationType.custom: 'custom',
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
