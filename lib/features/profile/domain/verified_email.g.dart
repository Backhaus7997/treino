// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'verified_email.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$VerifiedEmailImpl _$$VerifiedEmailImplFromJson(Map<String, dynamic> json) =>
    _$VerifiedEmailImpl(
      email: json['email'] as String? ?? '',
      verifiedAt: _$JsonConverterFromJson<Timestamp, DateTime>(
          json['verifiedAt'], const TimestampConverter().fromJson),
    );

Map<String, dynamic> _$$VerifiedEmailImplToJson(_$VerifiedEmailImpl instance) =>
    <String, dynamic>{
      'email': instance.email,
      'verifiedAt': _$JsonConverterToJson<Timestamp, DateTime>(
          instance.verifiedAt, const TimestampConverter().toJson),
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
