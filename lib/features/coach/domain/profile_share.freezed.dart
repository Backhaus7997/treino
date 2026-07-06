// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'profile_share.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

ProfileShare _$ProfileShareFromJson(Map<String, dynamic> json) {
  return _ProfileShare.fromJson(json);
}

/// @nodoc
mixin _$ProfileShare {
  /// The trainer this consent is for.
  String get trainerId =>
      throw _privateConstructorUsedError; // ── Shared personal fields (match UserProfile types exactly) ──────────
  String? get phone => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime? get bornAt => throw _privateConstructorUsedError;
  int? get heightCm => throw _privateConstructorUsedError;
  double? get bodyWeightKg => throw _privateConstructorUsedError;
  Gender? get gender => throw _privateConstructorUsedError;
  ExperienceLevel? get experienceLevel => throw _privateConstructorUsedError;

  /// Last time the athlete updated this document.
  @TimestampConverter()
  DateTime? get updatedAt => throw _privateConstructorUsedError;

  /// Serializes this ProfileShare to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ProfileShare
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ProfileShareCopyWith<ProfileShare> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ProfileShareCopyWith<$Res> {
  factory $ProfileShareCopyWith(
          ProfileShare value, $Res Function(ProfileShare) then) =
      _$ProfileShareCopyWithImpl<$Res, ProfileShare>;
  @useResult
  $Res call(
      {String trainerId,
      String? phone,
      @TimestampConverter() DateTime? bornAt,
      int? heightCm,
      double? bodyWeightKg,
      Gender? gender,
      ExperienceLevel? experienceLevel,
      @TimestampConverter() DateTime? updatedAt});
}

/// @nodoc
class _$ProfileShareCopyWithImpl<$Res, $Val extends ProfileShare>
    implements $ProfileShareCopyWith<$Res> {
  _$ProfileShareCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ProfileShare
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? trainerId = null,
    Object? phone = freezed,
    Object? bornAt = freezed,
    Object? heightCm = freezed,
    Object? bodyWeightKg = freezed,
    Object? gender = freezed,
    Object? experienceLevel = freezed,
    Object? updatedAt = freezed,
  }) {
    return _then(_value.copyWith(
      trainerId: null == trainerId
          ? _value.trainerId
          : trainerId // ignore: cast_nullable_to_non_nullable
              as String,
      phone: freezed == phone
          ? _value.phone
          : phone // ignore: cast_nullable_to_non_nullable
              as String?,
      bornAt: freezed == bornAt
          ? _value.bornAt
          : bornAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      heightCm: freezed == heightCm
          ? _value.heightCm
          : heightCm // ignore: cast_nullable_to_non_nullable
              as int?,
      bodyWeightKg: freezed == bodyWeightKg
          ? _value.bodyWeightKg
          : bodyWeightKg // ignore: cast_nullable_to_non_nullable
              as double?,
      gender: freezed == gender
          ? _value.gender
          : gender // ignore: cast_nullable_to_non_nullable
              as Gender?,
      experienceLevel: freezed == experienceLevel
          ? _value.experienceLevel
          : experienceLevel // ignore: cast_nullable_to_non_nullable
              as ExperienceLevel?,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ProfileShareImplCopyWith<$Res>
    implements $ProfileShareCopyWith<$Res> {
  factory _$$ProfileShareImplCopyWith(
          _$ProfileShareImpl value, $Res Function(_$ProfileShareImpl) then) =
      __$$ProfileShareImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String trainerId,
      String? phone,
      @TimestampConverter() DateTime? bornAt,
      int? heightCm,
      double? bodyWeightKg,
      Gender? gender,
      ExperienceLevel? experienceLevel,
      @TimestampConverter() DateTime? updatedAt});
}

/// @nodoc
class __$$ProfileShareImplCopyWithImpl<$Res>
    extends _$ProfileShareCopyWithImpl<$Res, _$ProfileShareImpl>
    implements _$$ProfileShareImplCopyWith<$Res> {
  __$$ProfileShareImplCopyWithImpl(
      _$ProfileShareImpl _value, $Res Function(_$ProfileShareImpl) _then)
      : super(_value, _then);

  /// Create a copy of ProfileShare
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? trainerId = null,
    Object? phone = freezed,
    Object? bornAt = freezed,
    Object? heightCm = freezed,
    Object? bodyWeightKg = freezed,
    Object? gender = freezed,
    Object? experienceLevel = freezed,
    Object? updatedAt = freezed,
  }) {
    return _then(_$ProfileShareImpl(
      trainerId: null == trainerId
          ? _value.trainerId
          : trainerId // ignore: cast_nullable_to_non_nullable
              as String,
      phone: freezed == phone
          ? _value.phone
          : phone // ignore: cast_nullable_to_non_nullable
              as String?,
      bornAt: freezed == bornAt
          ? _value.bornAt
          : bornAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      heightCm: freezed == heightCm
          ? _value.heightCm
          : heightCm // ignore: cast_nullable_to_non_nullable
              as int?,
      bodyWeightKg: freezed == bodyWeightKg
          ? _value.bodyWeightKg
          : bodyWeightKg // ignore: cast_nullable_to_non_nullable
              as double?,
      gender: freezed == gender
          ? _value.gender
          : gender // ignore: cast_nullable_to_non_nullable
              as Gender?,
      experienceLevel: freezed == experienceLevel
          ? _value.experienceLevel
          : experienceLevel // ignore: cast_nullable_to_non_nullable
              as ExperienceLevel?,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ProfileShareImpl implements _ProfileShare {
  const _$ProfileShareImpl(
      {required this.trainerId,
      this.phone,
      @TimestampConverter() this.bornAt,
      this.heightCm,
      this.bodyWeightKg,
      this.gender,
      this.experienceLevel,
      @TimestampConverter() this.updatedAt});

  factory _$ProfileShareImpl.fromJson(Map<String, dynamic> json) =>
      _$$ProfileShareImplFromJson(json);

  /// The trainer this consent is for.
  @override
  final String trainerId;
// ── Shared personal fields (match UserProfile types exactly) ──────────
  @override
  final String? phone;
  @override
  @TimestampConverter()
  final DateTime? bornAt;
  @override
  final int? heightCm;
  @override
  final double? bodyWeightKg;
  @override
  final Gender? gender;
  @override
  final ExperienceLevel? experienceLevel;

  /// Last time the athlete updated this document.
  @override
  @TimestampConverter()
  final DateTime? updatedAt;

  @override
  String toString() {
    return 'ProfileShare(trainerId: $trainerId, phone: $phone, bornAt: $bornAt, heightCm: $heightCm, bodyWeightKg: $bodyWeightKg, gender: $gender, experienceLevel: $experienceLevel, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ProfileShareImpl &&
            (identical(other.trainerId, trainerId) ||
                other.trainerId == trainerId) &&
            (identical(other.phone, phone) || other.phone == phone) &&
            (identical(other.bornAt, bornAt) || other.bornAt == bornAt) &&
            (identical(other.heightCm, heightCm) ||
                other.heightCm == heightCm) &&
            (identical(other.bodyWeightKg, bodyWeightKg) ||
                other.bodyWeightKg == bodyWeightKg) &&
            (identical(other.gender, gender) || other.gender == gender) &&
            (identical(other.experienceLevel, experienceLevel) ||
                other.experienceLevel == experienceLevel) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, trainerId, phone, bornAt,
      heightCm, bodyWeightKg, gender, experienceLevel, updatedAt);

  /// Create a copy of ProfileShare
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ProfileShareImplCopyWith<_$ProfileShareImpl> get copyWith =>
      __$$ProfileShareImplCopyWithImpl<_$ProfileShareImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ProfileShareImplToJson(
      this,
    );
  }
}

abstract class _ProfileShare implements ProfileShare {
  const factory _ProfileShare(
      {required final String trainerId,
      final String? phone,
      @TimestampConverter() final DateTime? bornAt,
      final int? heightCm,
      final double? bodyWeightKg,
      final Gender? gender,
      final ExperienceLevel? experienceLevel,
      @TimestampConverter() final DateTime? updatedAt}) = _$ProfileShareImpl;

  factory _ProfileShare.fromJson(Map<String, dynamic> json) =
      _$ProfileShareImpl.fromJson;

  /// The trainer this consent is for.
  @override
  String
      get trainerId; // ── Shared personal fields (match UserProfile types exactly) ──────────
  @override
  String? get phone;
  @override
  @TimestampConverter()
  DateTime? get bornAt;
  @override
  int? get heightCm;
  @override
  double? get bodyWeightKg;
  @override
  Gender? get gender;
  @override
  ExperienceLevel? get experienceLevel;

  /// Last time the athlete updated this document.
  @override
  @TimestampConverter()
  DateTime? get updatedAt;

  /// Create a copy of ProfileShare
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ProfileShareImplCopyWith<_$ProfileShareImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
