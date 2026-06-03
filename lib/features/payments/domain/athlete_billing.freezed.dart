// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'athlete_billing.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

AthleteBilling _$AthleteBillingFromJson(Map<String, dynamic> json) {
  return _AthleteBilling.fromJson(json);
}

/// @nodoc
mixin _$AthleteBilling {
  String get trainerId => throw _privateConstructorUsedError;
  String get athleteId => throw _privateConstructorUsedError;
  int get amountArs => throw _privateConstructorUsedError;
  BillingCadence get cadence => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get updatedAt => throw _privateConstructorUsedError;

  /// Serializes this AthleteBilling to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of AthleteBilling
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $AthleteBillingCopyWith<AthleteBilling> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AthleteBillingCopyWith<$Res> {
  factory $AthleteBillingCopyWith(
          AthleteBilling value, $Res Function(AthleteBilling) then) =
      _$AthleteBillingCopyWithImpl<$Res, AthleteBilling>;
  @useResult
  $Res call(
      {String trainerId,
      String athleteId,
      int amountArs,
      BillingCadence cadence,
      @TimestampConverter() DateTime updatedAt});
}

/// @nodoc
class _$AthleteBillingCopyWithImpl<$Res, $Val extends AthleteBilling>
    implements $AthleteBillingCopyWith<$Res> {
  _$AthleteBillingCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of AthleteBilling
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? trainerId = null,
    Object? athleteId = null,
    Object? amountArs = null,
    Object? cadence = null,
    Object? updatedAt = null,
  }) {
    return _then(_value.copyWith(
      trainerId: null == trainerId
          ? _value.trainerId
          : trainerId // ignore: cast_nullable_to_non_nullable
              as String,
      athleteId: null == athleteId
          ? _value.athleteId
          : athleteId // ignore: cast_nullable_to_non_nullable
              as String,
      amountArs: null == amountArs
          ? _value.amountArs
          : amountArs // ignore: cast_nullable_to_non_nullable
              as int,
      cadence: null == cadence
          ? _value.cadence
          : cadence // ignore: cast_nullable_to_non_nullable
              as BillingCadence,
      updatedAt: null == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$AthleteBillingImplCopyWith<$Res>
    implements $AthleteBillingCopyWith<$Res> {
  factory _$$AthleteBillingImplCopyWith(_$AthleteBillingImpl value,
          $Res Function(_$AthleteBillingImpl) then) =
      __$$AthleteBillingImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String trainerId,
      String athleteId,
      int amountArs,
      BillingCadence cadence,
      @TimestampConverter() DateTime updatedAt});
}

/// @nodoc
class __$$AthleteBillingImplCopyWithImpl<$Res>
    extends _$AthleteBillingCopyWithImpl<$Res, _$AthleteBillingImpl>
    implements _$$AthleteBillingImplCopyWith<$Res> {
  __$$AthleteBillingImplCopyWithImpl(
      _$AthleteBillingImpl _value, $Res Function(_$AthleteBillingImpl) _then)
      : super(_value, _then);

  /// Create a copy of AthleteBilling
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? trainerId = null,
    Object? athleteId = null,
    Object? amountArs = null,
    Object? cadence = null,
    Object? updatedAt = null,
  }) {
    return _then(_$AthleteBillingImpl(
      trainerId: null == trainerId
          ? _value.trainerId
          : trainerId // ignore: cast_nullable_to_non_nullable
              as String,
      athleteId: null == athleteId
          ? _value.athleteId
          : athleteId // ignore: cast_nullable_to_non_nullable
              as String,
      amountArs: null == amountArs
          ? _value.amountArs
          : amountArs // ignore: cast_nullable_to_non_nullable
              as int,
      cadence: null == cadence
          ? _value.cadence
          : cadence // ignore: cast_nullable_to_non_nullable
              as BillingCadence,
      updatedAt: null == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$AthleteBillingImpl implements _AthleteBilling {
  const _$AthleteBillingImpl(
      {required this.trainerId,
      required this.athleteId,
      required this.amountArs,
      required this.cadence,
      @TimestampConverter() required this.updatedAt});

  factory _$AthleteBillingImpl.fromJson(Map<String, dynamic> json) =>
      _$$AthleteBillingImplFromJson(json);

  @override
  final String trainerId;
  @override
  final String athleteId;
  @override
  final int amountArs;
  @override
  final BillingCadence cadence;
  @override
  @TimestampConverter()
  final DateTime updatedAt;

  @override
  String toString() {
    return 'AthleteBilling(trainerId: $trainerId, athleteId: $athleteId, amountArs: $amountArs, cadence: $cadence, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AthleteBillingImpl &&
            (identical(other.trainerId, trainerId) ||
                other.trainerId == trainerId) &&
            (identical(other.athleteId, athleteId) ||
                other.athleteId == athleteId) &&
            (identical(other.amountArs, amountArs) ||
                other.amountArs == amountArs) &&
            (identical(other.cadence, cadence) || other.cadence == cadence) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType, trainerId, athleteId, amountArs, cadence, updatedAt);

  /// Create a copy of AthleteBilling
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AthleteBillingImplCopyWith<_$AthleteBillingImpl> get copyWith =>
      __$$AthleteBillingImplCopyWithImpl<_$AthleteBillingImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AthleteBillingImplToJson(
      this,
    );
  }
}

abstract class _AthleteBilling implements AthleteBilling {
  const factory _AthleteBilling(
          {required final String trainerId,
          required final String athleteId,
          required final int amountArs,
          required final BillingCadence cadence,
          @TimestampConverter() required final DateTime updatedAt}) =
      _$AthleteBillingImpl;

  factory _AthleteBilling.fromJson(Map<String, dynamic> json) =
      _$AthleteBillingImpl.fromJson;

  @override
  String get trainerId;
  @override
  String get athleteId;
  @override
  int get amountArs;
  @override
  BillingCadence get cadence;
  @override
  @TimestampConverter()
  DateTime get updatedAt;

  /// Create a copy of AthleteBilling
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AthleteBillingImplCopyWith<_$AthleteBillingImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
