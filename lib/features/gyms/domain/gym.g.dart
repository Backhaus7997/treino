// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gym.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$GymImpl _$$GymImplFromJson(Map<String, dynamic> json) => _$GymImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      address: json['address'] as String?,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      geohash: json['geohash'] as String,
      source: $enumDecode(_$GymSourceEnumMap, json['source']),
      createdBy: json['createdBy'] as String?,
      createdAt:
          const TimestampConverter().fromJson(json['createdAt'] as Timestamp),
    );

Map<String, dynamic> _$$GymImplToJson(_$GymImpl instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'address': instance.address,
      'lat': instance.lat,
      'lng': instance.lng,
      'geohash': instance.geohash,
      'source': _$GymSourceEnumMap[instance.source]!,
      'createdBy': instance.createdBy,
      'createdAt': const TimestampConverter().toJson(instance.createdAt),
    };

const _$GymSourceEnumMap = {
  GymSource.seed: 'seed',
  GymSource.selfService: 'self-service',
};
