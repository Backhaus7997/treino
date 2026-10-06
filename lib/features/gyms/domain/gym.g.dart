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
      brandId: json['brandId'] as String?,
      brandName: json['brandName'] as String?,
      branchName: json['branchName'] as String?,
      city: json['city'] as String?,
      province: json['province'] as String?,
      coordsFetchedAt: _$JsonConverterFromJson<Timestamp, DateTime>(
          json['coordsFetchedAt'], const TimestampConverter().fromJson),
      placeStatus: json['placeStatus'] as String?,
      nameNeeded: json['nameNeeded'] as bool? ?? false,
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
      'brandId': instance.brandId,
      'brandName': instance.brandName,
      'branchName': instance.branchName,
      'city': instance.city,
      'province': instance.province,
      'coordsFetchedAt': _$JsonConverterToJson<Timestamp, DateTime>(
          instance.coordsFetchedAt, const TimestampConverter().toJson),
      'placeStatus': instance.placeStatus,
      'nameNeeded': instance.nameNeeded,
    };

const _$GymSourceEnumMap = {
  GymSource.seed: 'seed',
  GymSource.selfService: 'self-service',
  GymSource.googlePlaces: 'google-places',
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
