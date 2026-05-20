// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'trainer_public_profile.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

TrainerPublicProfile _$TrainerPublicProfileFromJson(Map<String, dynamic> json) {
  return _TrainerPublicProfile.fromJson(json);
}

/// @nodoc
mixin _$TrainerPublicProfile {
  String get uid => throw _privateConstructorUsedError;
  String? get displayName => throw _privateConstructorUsedError;
  String? get displayNameLowercase => throw _privateConstructorUsedError;
  String? get avatarUrl => throw _privateConstructorUsedError;
  String? get trainerBio => throw _privateConstructorUsedError;
  @JsonKey(fromJson: _specialtyFromJson, toJson: _specialtyToJson)
  TrainerSpecialty? get trainerSpecialty => throw _privateConstructorUsedError;
  String? get trainerGeohash => throw _privateConstructorUsedError;
  double? get trainerLatitude => throw _privateConstructorUsedError;
  double? get trainerLongitude => throw _privateConstructorUsedError;
  int? get trainerMonthlyRate => throw _privateConstructorUsedError;

  /// Serializes this TrainerPublicProfile to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of TrainerPublicProfile
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $TrainerPublicProfileCopyWith<TrainerPublicProfile> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TrainerPublicProfileCopyWith<$Res> {
  factory $TrainerPublicProfileCopyWith(TrainerPublicProfile value,
          $Res Function(TrainerPublicProfile) then) =
      _$TrainerPublicProfileCopyWithImpl<$Res, TrainerPublicProfile>;
  @useResult
  $Res call(
      {String uid,
      String? displayName,
      String? displayNameLowercase,
      String? avatarUrl,
      String? trainerBio,
      @JsonKey(fromJson: _specialtyFromJson, toJson: _specialtyToJson)
      TrainerSpecialty? trainerSpecialty,
      String? trainerGeohash,
      double? trainerLatitude,
      double? trainerLongitude,
      int? trainerMonthlyRate});
}

/// @nodoc
class _$TrainerPublicProfileCopyWithImpl<$Res,
        $Val extends TrainerPublicProfile>
    implements $TrainerPublicProfileCopyWith<$Res> {
  _$TrainerPublicProfileCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of TrainerPublicProfile
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? uid = null,
    Object? displayName = freezed,
    Object? displayNameLowercase = freezed,
    Object? avatarUrl = freezed,
    Object? trainerBio = freezed,
    Object? trainerSpecialty = freezed,
    Object? trainerGeohash = freezed,
    Object? trainerLatitude = freezed,
    Object? trainerLongitude = freezed,
    Object? trainerMonthlyRate = freezed,
  }) {
    return _then(_value.copyWith(
      uid: null == uid
          ? _value.uid
          : uid // ignore: cast_nullable_to_non_nullable
              as String,
      displayName: freezed == displayName
          ? _value.displayName
          : displayName // ignore: cast_nullable_to_non_nullable
              as String?,
      displayNameLowercase: freezed == displayNameLowercase
          ? _value.displayNameLowercase
          : displayNameLowercase // ignore: cast_nullable_to_non_nullable
              as String?,
      avatarUrl: freezed == avatarUrl
          ? _value.avatarUrl
          : avatarUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      trainerBio: freezed == trainerBio
          ? _value.trainerBio
          : trainerBio // ignore: cast_nullable_to_non_nullable
              as String?,
      trainerSpecialty: freezed == trainerSpecialty
          ? _value.trainerSpecialty
          : trainerSpecialty // ignore: cast_nullable_to_non_nullable
              as TrainerSpecialty?,
      trainerGeohash: freezed == trainerGeohash
          ? _value.trainerGeohash
          : trainerGeohash // ignore: cast_nullable_to_non_nullable
              as String?,
      trainerLatitude: freezed == trainerLatitude
          ? _value.trainerLatitude
          : trainerLatitude // ignore: cast_nullable_to_non_nullable
              as double?,
      trainerLongitude: freezed == trainerLongitude
          ? _value.trainerLongitude
          : trainerLongitude // ignore: cast_nullable_to_non_nullable
              as double?,
      trainerMonthlyRate: freezed == trainerMonthlyRate
          ? _value.trainerMonthlyRate
          : trainerMonthlyRate // ignore: cast_nullable_to_non_nullable
              as int?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$TrainerPublicProfileImplCopyWith<$Res>
    implements $TrainerPublicProfileCopyWith<$Res> {
  factory _$$TrainerPublicProfileImplCopyWith(_$TrainerPublicProfileImpl value,
          $Res Function(_$TrainerPublicProfileImpl) then) =
      __$$TrainerPublicProfileImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String uid,
      String? displayName,
      String? displayNameLowercase,
      String? avatarUrl,
      String? trainerBio,
      @JsonKey(fromJson: _specialtyFromJson, toJson: _specialtyToJson)
      TrainerSpecialty? trainerSpecialty,
      String? trainerGeohash,
      double? trainerLatitude,
      double? trainerLongitude,
      int? trainerMonthlyRate});
}

/// @nodoc
class __$$TrainerPublicProfileImplCopyWithImpl<$Res>
    extends _$TrainerPublicProfileCopyWithImpl<$Res, _$TrainerPublicProfileImpl>
    implements _$$TrainerPublicProfileImplCopyWith<$Res> {
  __$$TrainerPublicProfileImplCopyWithImpl(_$TrainerPublicProfileImpl _value,
      $Res Function(_$TrainerPublicProfileImpl) _then)
      : super(_value, _then);

  /// Create a copy of TrainerPublicProfile
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? uid = null,
    Object? displayName = freezed,
    Object? displayNameLowercase = freezed,
    Object? avatarUrl = freezed,
    Object? trainerBio = freezed,
    Object? trainerSpecialty = freezed,
    Object? trainerGeohash = freezed,
    Object? trainerLatitude = freezed,
    Object? trainerLongitude = freezed,
    Object? trainerMonthlyRate = freezed,
  }) {
    return _then(_$TrainerPublicProfileImpl(
      uid: null == uid
          ? _value.uid
          : uid // ignore: cast_nullable_to_non_nullable
              as String,
      displayName: freezed == displayName
          ? _value.displayName
          : displayName // ignore: cast_nullable_to_non_nullable
              as String?,
      displayNameLowercase: freezed == displayNameLowercase
          ? _value.displayNameLowercase
          : displayNameLowercase // ignore: cast_nullable_to_non_nullable
              as String?,
      avatarUrl: freezed == avatarUrl
          ? _value.avatarUrl
          : avatarUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      trainerBio: freezed == trainerBio
          ? _value.trainerBio
          : trainerBio // ignore: cast_nullable_to_non_nullable
              as String?,
      trainerSpecialty: freezed == trainerSpecialty
          ? _value.trainerSpecialty
          : trainerSpecialty // ignore: cast_nullable_to_non_nullable
              as TrainerSpecialty?,
      trainerGeohash: freezed == trainerGeohash
          ? _value.trainerGeohash
          : trainerGeohash // ignore: cast_nullable_to_non_nullable
              as String?,
      trainerLatitude: freezed == trainerLatitude
          ? _value.trainerLatitude
          : trainerLatitude // ignore: cast_nullable_to_non_nullable
              as double?,
      trainerLongitude: freezed == trainerLongitude
          ? _value.trainerLongitude
          : trainerLongitude // ignore: cast_nullable_to_non_nullable
              as double?,
      trainerMonthlyRate: freezed == trainerMonthlyRate
          ? _value.trainerMonthlyRate
          : trainerMonthlyRate // ignore: cast_nullable_to_non_nullable
              as int?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$TrainerPublicProfileImpl implements _TrainerPublicProfile {
  const _$TrainerPublicProfileImpl(
      {required this.uid,
      this.displayName,
      this.displayNameLowercase,
      this.avatarUrl,
      this.trainerBio,
      @JsonKey(fromJson: _specialtyFromJson, toJson: _specialtyToJson)
      this.trainerSpecialty,
      this.trainerGeohash,
      this.trainerLatitude,
      this.trainerLongitude,
      this.trainerMonthlyRate});

  factory _$TrainerPublicProfileImpl.fromJson(Map<String, dynamic> json) =>
      _$$TrainerPublicProfileImplFromJson(json);

  @override
  final String uid;
  @override
  final String? displayName;
  @override
  final String? displayNameLowercase;
  @override
  final String? avatarUrl;
  @override
  final String? trainerBio;
  @override
  @JsonKey(fromJson: _specialtyFromJson, toJson: _specialtyToJson)
  final TrainerSpecialty? trainerSpecialty;
  @override
  final String? trainerGeohash;
  @override
  final double? trainerLatitude;
  @override
  final double? trainerLongitude;
  @override
  final int? trainerMonthlyRate;

  @override
  String toString() {
    return 'TrainerPublicProfile(uid: $uid, displayName: $displayName, displayNameLowercase: $displayNameLowercase, avatarUrl: $avatarUrl, trainerBio: $trainerBio, trainerSpecialty: $trainerSpecialty, trainerGeohash: $trainerGeohash, trainerLatitude: $trainerLatitude, trainerLongitude: $trainerLongitude, trainerMonthlyRate: $trainerMonthlyRate)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TrainerPublicProfileImpl &&
            (identical(other.uid, uid) || other.uid == uid) &&
            (identical(other.displayName, displayName) ||
                other.displayName == displayName) &&
            (identical(other.displayNameLowercase, displayNameLowercase) ||
                other.displayNameLowercase == displayNameLowercase) &&
            (identical(other.avatarUrl, avatarUrl) ||
                other.avatarUrl == avatarUrl) &&
            (identical(other.trainerBio, trainerBio) ||
                other.trainerBio == trainerBio) &&
            (identical(other.trainerSpecialty, trainerSpecialty) ||
                other.trainerSpecialty == trainerSpecialty) &&
            (identical(other.trainerGeohash, trainerGeohash) ||
                other.trainerGeohash == trainerGeohash) &&
            (identical(other.trainerLatitude, trainerLatitude) ||
                other.trainerLatitude == trainerLatitude) &&
            (identical(other.trainerLongitude, trainerLongitude) ||
                other.trainerLongitude == trainerLongitude) &&
            (identical(other.trainerMonthlyRate, trainerMonthlyRate) ||
                other.trainerMonthlyRate == trainerMonthlyRate));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      uid,
      displayName,
      displayNameLowercase,
      avatarUrl,
      trainerBio,
      trainerSpecialty,
      trainerGeohash,
      trainerLatitude,
      trainerLongitude,
      trainerMonthlyRate);

  /// Create a copy of TrainerPublicProfile
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TrainerPublicProfileImplCopyWith<_$TrainerPublicProfileImpl>
      get copyWith =>
          __$$TrainerPublicProfileImplCopyWithImpl<_$TrainerPublicProfileImpl>(
              this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$TrainerPublicProfileImplToJson(
      this,
    );
  }
}

abstract class _TrainerPublicProfile implements TrainerPublicProfile {
  const factory _TrainerPublicProfile(
      {required final String uid,
      final String? displayName,
      final String? displayNameLowercase,
      final String? avatarUrl,
      final String? trainerBio,
      @JsonKey(fromJson: _specialtyFromJson, toJson: _specialtyToJson)
      final TrainerSpecialty? trainerSpecialty,
      final String? trainerGeohash,
      final double? trainerLatitude,
      final double? trainerLongitude,
      final int? trainerMonthlyRate}) = _$TrainerPublicProfileImpl;

  factory _TrainerPublicProfile.fromJson(Map<String, dynamic> json) =
      _$TrainerPublicProfileImpl.fromJson;

  @override
  String get uid;
  @override
  String? get displayName;
  @override
  String? get displayNameLowercase;
  @override
  String? get avatarUrl;
  @override
  String? get trainerBio;
  @override
  @JsonKey(fromJson: _specialtyFromJson, toJson: _specialtyToJson)
  TrainerSpecialty? get trainerSpecialty;
  @override
  String? get trainerGeohash;
  @override
  double? get trainerLatitude;
  @override
  double? get trainerLongitude;
  @override
  int? get trainerMonthlyRate;

  /// Create a copy of TrainerPublicProfile
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TrainerPublicProfileImplCopyWith<_$TrainerPublicProfileImpl>
      get copyWith => throw _privateConstructorUsedError;
}
