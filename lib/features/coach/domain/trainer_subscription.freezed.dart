// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'trainer_subscription.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

TrainerSubscription _$TrainerSubscriptionFromJson(Map<String, dynamic> json) {
  return _TrainerSubscription.fromJson(json);
}

/// @nodoc
mixin _$TrainerSubscription {
  SubscriptionTier get tier => throw _privateConstructorUsedError;
  SubscriptionStatus get status => throw _privateConstructorUsedError;
  SubscriptionCycle? get cycle =>
      throw _privateConstructorUsedError; // Límite de peso ponderado cacheado (denormalizado) — el CF lo escribe
// junto con `tier` para que UI/rules lean sin lookup. Nunca confiar en
// un valor client-provisto (rules lo pinnea CF-write-only).
  int get weightLimit => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime? get currentPeriodEnd => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime? get graceUntil => throw _privateConstructorUsedError;
  String? get mpPreapprovalId => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime? get updatedByWebhookAt => throw _privateConstructorUsedError;
  String? get lastMpEventId => throw _privateConstructorUsedError;

  /// Serializes this TrainerSubscription to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of TrainerSubscription
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $TrainerSubscriptionCopyWith<TrainerSubscription> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TrainerSubscriptionCopyWith<$Res> {
  factory $TrainerSubscriptionCopyWith(
          TrainerSubscription value, $Res Function(TrainerSubscription) then) =
      _$TrainerSubscriptionCopyWithImpl<$Res, TrainerSubscription>;
  @useResult
  $Res call(
      {SubscriptionTier tier,
      SubscriptionStatus status,
      SubscriptionCycle? cycle,
      int weightLimit,
      @TimestampConverter() DateTime? currentPeriodEnd,
      @TimestampConverter() DateTime? graceUntil,
      String? mpPreapprovalId,
      @TimestampConverter() DateTime? updatedByWebhookAt,
      String? lastMpEventId});
}

/// @nodoc
class _$TrainerSubscriptionCopyWithImpl<$Res, $Val extends TrainerSubscription>
    implements $TrainerSubscriptionCopyWith<$Res> {
  _$TrainerSubscriptionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of TrainerSubscription
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? tier = null,
    Object? status = null,
    Object? cycle = freezed,
    Object? weightLimit = null,
    Object? currentPeriodEnd = freezed,
    Object? graceUntil = freezed,
    Object? mpPreapprovalId = freezed,
    Object? updatedByWebhookAt = freezed,
    Object? lastMpEventId = freezed,
  }) {
    return _then(_value.copyWith(
      tier: null == tier
          ? _value.tier
          : tier // ignore: cast_nullable_to_non_nullable
              as SubscriptionTier,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as SubscriptionStatus,
      cycle: freezed == cycle
          ? _value.cycle
          : cycle // ignore: cast_nullable_to_non_nullable
              as SubscriptionCycle?,
      weightLimit: null == weightLimit
          ? _value.weightLimit
          : weightLimit // ignore: cast_nullable_to_non_nullable
              as int,
      currentPeriodEnd: freezed == currentPeriodEnd
          ? _value.currentPeriodEnd
          : currentPeriodEnd // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      graceUntil: freezed == graceUntil
          ? _value.graceUntil
          : graceUntil // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      mpPreapprovalId: freezed == mpPreapprovalId
          ? _value.mpPreapprovalId
          : mpPreapprovalId // ignore: cast_nullable_to_non_nullable
              as String?,
      updatedByWebhookAt: freezed == updatedByWebhookAt
          ? _value.updatedByWebhookAt
          : updatedByWebhookAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      lastMpEventId: freezed == lastMpEventId
          ? _value.lastMpEventId
          : lastMpEventId // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$TrainerSubscriptionImplCopyWith<$Res>
    implements $TrainerSubscriptionCopyWith<$Res> {
  factory _$$TrainerSubscriptionImplCopyWith(_$TrainerSubscriptionImpl value,
          $Res Function(_$TrainerSubscriptionImpl) then) =
      __$$TrainerSubscriptionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {SubscriptionTier tier,
      SubscriptionStatus status,
      SubscriptionCycle? cycle,
      int weightLimit,
      @TimestampConverter() DateTime? currentPeriodEnd,
      @TimestampConverter() DateTime? graceUntil,
      String? mpPreapprovalId,
      @TimestampConverter() DateTime? updatedByWebhookAt,
      String? lastMpEventId});
}

/// @nodoc
class __$$TrainerSubscriptionImplCopyWithImpl<$Res>
    extends _$TrainerSubscriptionCopyWithImpl<$Res, _$TrainerSubscriptionImpl>
    implements _$$TrainerSubscriptionImplCopyWith<$Res> {
  __$$TrainerSubscriptionImplCopyWithImpl(_$TrainerSubscriptionImpl _value,
      $Res Function(_$TrainerSubscriptionImpl) _then)
      : super(_value, _then);

  /// Create a copy of TrainerSubscription
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? tier = null,
    Object? status = null,
    Object? cycle = freezed,
    Object? weightLimit = null,
    Object? currentPeriodEnd = freezed,
    Object? graceUntil = freezed,
    Object? mpPreapprovalId = freezed,
    Object? updatedByWebhookAt = freezed,
    Object? lastMpEventId = freezed,
  }) {
    return _then(_$TrainerSubscriptionImpl(
      tier: null == tier
          ? _value.tier
          : tier // ignore: cast_nullable_to_non_nullable
              as SubscriptionTier,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as SubscriptionStatus,
      cycle: freezed == cycle
          ? _value.cycle
          : cycle // ignore: cast_nullable_to_non_nullable
              as SubscriptionCycle?,
      weightLimit: null == weightLimit
          ? _value.weightLimit
          : weightLimit // ignore: cast_nullable_to_non_nullable
              as int,
      currentPeriodEnd: freezed == currentPeriodEnd
          ? _value.currentPeriodEnd
          : currentPeriodEnd // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      graceUntil: freezed == graceUntil
          ? _value.graceUntil
          : graceUntil // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      mpPreapprovalId: freezed == mpPreapprovalId
          ? _value.mpPreapprovalId
          : mpPreapprovalId // ignore: cast_nullable_to_non_nullable
              as String?,
      updatedByWebhookAt: freezed == updatedByWebhookAt
          ? _value.updatedByWebhookAt
          : updatedByWebhookAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      lastMpEventId: freezed == lastMpEventId
          ? _value.lastMpEventId
          : lastMpEventId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$TrainerSubscriptionImpl implements _TrainerSubscription {
  const _$TrainerSubscriptionImpl(
      {required this.tier,
      required this.status,
      this.cycle,
      required this.weightLimit,
      @TimestampConverter() this.currentPeriodEnd,
      @TimestampConverter() this.graceUntil,
      this.mpPreapprovalId,
      @TimestampConverter() this.updatedByWebhookAt,
      this.lastMpEventId});

  factory _$TrainerSubscriptionImpl.fromJson(Map<String, dynamic> json) =>
      _$$TrainerSubscriptionImplFromJson(json);

  @override
  final SubscriptionTier tier;
  @override
  final SubscriptionStatus status;
  @override
  final SubscriptionCycle? cycle;
// Límite de peso ponderado cacheado (denormalizado) — el CF lo escribe
// junto con `tier` para que UI/rules lean sin lookup. Nunca confiar en
// un valor client-provisto (rules lo pinnea CF-write-only).
  @override
  final int weightLimit;
  @override
  @TimestampConverter()
  final DateTime? currentPeriodEnd;
  @override
  @TimestampConverter()
  final DateTime? graceUntil;
  @override
  final String? mpPreapprovalId;
  @override
  @TimestampConverter()
  final DateTime? updatedByWebhookAt;
  @override
  final String? lastMpEventId;

  @override
  String toString() {
    return 'TrainerSubscription(tier: $tier, status: $status, cycle: $cycle, weightLimit: $weightLimit, currentPeriodEnd: $currentPeriodEnd, graceUntil: $graceUntil, mpPreapprovalId: $mpPreapprovalId, updatedByWebhookAt: $updatedByWebhookAt, lastMpEventId: $lastMpEventId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TrainerSubscriptionImpl &&
            (identical(other.tier, tier) || other.tier == tier) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.cycle, cycle) || other.cycle == cycle) &&
            (identical(other.weightLimit, weightLimit) ||
                other.weightLimit == weightLimit) &&
            (identical(other.currentPeriodEnd, currentPeriodEnd) ||
                other.currentPeriodEnd == currentPeriodEnd) &&
            (identical(other.graceUntil, graceUntil) ||
                other.graceUntil == graceUntil) &&
            (identical(other.mpPreapprovalId, mpPreapprovalId) ||
                other.mpPreapprovalId == mpPreapprovalId) &&
            (identical(other.updatedByWebhookAt, updatedByWebhookAt) ||
                other.updatedByWebhookAt == updatedByWebhookAt) &&
            (identical(other.lastMpEventId, lastMpEventId) ||
                other.lastMpEventId == lastMpEventId));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      tier,
      status,
      cycle,
      weightLimit,
      currentPeriodEnd,
      graceUntil,
      mpPreapprovalId,
      updatedByWebhookAt,
      lastMpEventId);

  /// Create a copy of TrainerSubscription
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TrainerSubscriptionImplCopyWith<_$TrainerSubscriptionImpl> get copyWith =>
      __$$TrainerSubscriptionImplCopyWithImpl<_$TrainerSubscriptionImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$TrainerSubscriptionImplToJson(
      this,
    );
  }
}

abstract class _TrainerSubscription implements TrainerSubscription {
  const factory _TrainerSubscription(
      {required final SubscriptionTier tier,
      required final SubscriptionStatus status,
      final SubscriptionCycle? cycle,
      required final int weightLimit,
      @TimestampConverter() final DateTime? currentPeriodEnd,
      @TimestampConverter() final DateTime? graceUntil,
      final String? mpPreapprovalId,
      @TimestampConverter() final DateTime? updatedByWebhookAt,
      final String? lastMpEventId}) = _$TrainerSubscriptionImpl;

  factory _TrainerSubscription.fromJson(Map<String, dynamic> json) =
      _$TrainerSubscriptionImpl.fromJson;

  @override
  SubscriptionTier get tier;
  @override
  SubscriptionStatus get status;
  @override
  SubscriptionCycle?
      get cycle; // Límite de peso ponderado cacheado (denormalizado) — el CF lo escribe
// junto con `tier` para que UI/rules lean sin lookup. Nunca confiar en
// un valor client-provisto (rules lo pinnea CF-write-only).
  @override
  int get weightLimit;
  @override
  @TimestampConverter()
  DateTime? get currentPeriodEnd;
  @override
  @TimestampConverter()
  DateTime? get graceUntil;
  @override
  String? get mpPreapprovalId;
  @override
  @TimestampConverter()
  DateTime? get updatedByWebhookAt;
  @override
  String? get lastMpEventId;

  /// Create a copy of TrainerSubscription
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TrainerSubscriptionImplCopyWith<_$TrainerSubscriptionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
