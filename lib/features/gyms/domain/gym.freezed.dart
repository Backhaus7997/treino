// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'gym.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Gym _$GymFromJson(Map<String, dynamic> json) {
  return _Gym.fromJson(json);
}

/// @nodoc
mixin _$Gym {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String? get address => throw _privateConstructorUsedError;
  double get lat => throw _privateConstructorUsedError;
  double get lng => throw _privateConstructorUsedError;
  String get geohash => throw _privateConstructorUsedError;
  GymSource get source => throw _privateConstructorUsedError;
  String? get createdBy => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get createdAt => throw _privateConstructorUsedError;

  /// Serializes this Gym to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Gym
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $GymCopyWith<Gym> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $GymCopyWith<$Res> {
  factory $GymCopyWith(Gym value, $Res Function(Gym) then) =
      _$GymCopyWithImpl<$Res, Gym>;
  @useResult
  $Res call(
      {String id,
      String name,
      String? address,
      double lat,
      double lng,
      String geohash,
      GymSource source,
      String? createdBy,
      @TimestampConverter() DateTime createdAt});
}

/// @nodoc
class _$GymCopyWithImpl<$Res, $Val extends Gym> implements $GymCopyWith<$Res> {
  _$GymCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Gym
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? address = freezed,
    Object? lat = null,
    Object? lng = null,
    Object? geohash = null,
    Object? source = null,
    Object? createdBy = freezed,
    Object? createdAt = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      address: freezed == address
          ? _value.address
          : address // ignore: cast_nullable_to_non_nullable
              as String?,
      lat: null == lat
          ? _value.lat
          : lat // ignore: cast_nullable_to_non_nullable
              as double,
      lng: null == lng
          ? _value.lng
          : lng // ignore: cast_nullable_to_non_nullable
              as double,
      geohash: null == geohash
          ? _value.geohash
          : geohash // ignore: cast_nullable_to_non_nullable
              as String,
      source: null == source
          ? _value.source
          : source // ignore: cast_nullable_to_non_nullable
              as GymSource,
      createdBy: freezed == createdBy
          ? _value.createdBy
          : createdBy // ignore: cast_nullable_to_non_nullable
              as String?,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$GymImplCopyWith<$Res> implements $GymCopyWith<$Res> {
  factory _$$GymImplCopyWith(_$GymImpl value, $Res Function(_$GymImpl) then) =
      __$$GymImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      String? address,
      double lat,
      double lng,
      String geohash,
      GymSource source,
      String? createdBy,
      @TimestampConverter() DateTime createdAt});
}

/// @nodoc
class __$$GymImplCopyWithImpl<$Res> extends _$GymCopyWithImpl<$Res, _$GymImpl>
    implements _$$GymImplCopyWith<$Res> {
  __$$GymImplCopyWithImpl(_$GymImpl _value, $Res Function(_$GymImpl) _then)
      : super(_value, _then);

  /// Create a copy of Gym
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? address = freezed,
    Object? lat = null,
    Object? lng = null,
    Object? geohash = null,
    Object? source = null,
    Object? createdBy = freezed,
    Object? createdAt = null,
  }) {
    return _then(_$GymImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      address: freezed == address
          ? _value.address
          : address // ignore: cast_nullable_to_non_nullable
              as String?,
      lat: null == lat
          ? _value.lat
          : lat // ignore: cast_nullable_to_non_nullable
              as double,
      lng: null == lng
          ? _value.lng
          : lng // ignore: cast_nullable_to_non_nullable
              as double,
      geohash: null == geohash
          ? _value.geohash
          : geohash // ignore: cast_nullable_to_non_nullable
              as String,
      source: null == source
          ? _value.source
          : source // ignore: cast_nullable_to_non_nullable
              as GymSource,
      createdBy: freezed == createdBy
          ? _value.createdBy
          : createdBy // ignore: cast_nullable_to_non_nullable
              as String?,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$GymImpl implements _Gym {
  const _$GymImpl(
      {required this.id,
      required this.name,
      this.address,
      required this.lat,
      required this.lng,
      required this.geohash,
      required this.source,
      this.createdBy,
      @TimestampConverter() required this.createdAt});

  factory _$GymImpl.fromJson(Map<String, dynamic> json) =>
      _$$GymImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final String? address;
  @override
  final double lat;
  @override
  final double lng;
  @override
  final String geohash;
  @override
  final GymSource source;
  @override
  final String? createdBy;
  @override
  @TimestampConverter()
  final DateTime createdAt;

  @override
  String toString() {
    return 'Gym(id: $id, name: $name, address: $address, lat: $lat, lng: $lng, geohash: $geohash, source: $source, createdBy: $createdBy, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$GymImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.address, address) || other.address == address) &&
            (identical(other.lat, lat) || other.lat == lat) &&
            (identical(other.lng, lng) || other.lng == lng) &&
            (identical(other.geohash, geohash) || other.geohash == geohash) &&
            (identical(other.source, source) || other.source == source) &&
            (identical(other.createdBy, createdBy) ||
                other.createdBy == createdBy) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, address, lat, lng,
      geohash, source, createdBy, createdAt);

  /// Create a copy of Gym
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$GymImplCopyWith<_$GymImpl> get copyWith =>
      __$$GymImplCopyWithImpl<_$GymImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$GymImplToJson(
      this,
    );
  }
}

abstract class _Gym implements Gym {
  const factory _Gym(
      {required final String id,
      required final String name,
      final String? address,
      required final double lat,
      required final double lng,
      required final String geohash,
      required final GymSource source,
      final String? createdBy,
      @TimestampConverter() required final DateTime createdAt}) = _$GymImpl;

  factory _Gym.fromJson(Map<String, dynamic> json) = _$GymImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String? get address;
  @override
  double get lat;
  @override
  double get lng;
  @override
  String get geohash;
  @override
  GymSource get source;
  @override
  String? get createdBy;
  @override
  @TimestampConverter()
  DateTime get createdAt;

  /// Create a copy of Gym
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$GymImplCopyWith<_$GymImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
