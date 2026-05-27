// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'commercial_plan.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

CommercialPlan _$CommercialPlanFromJson(Map<String, dynamic> json) {
  return _CommercialPlan.fromJson(json);
}

/// @nodoc
mixin _$CommercialPlan {
  String get id => throw _privateConstructorUsedError;
  String get trainerId => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String get shortDescription => throw _privateConstructorUsedError;
  int get priceArs => throw _privateConstructorUsedError;
  int get durationMonths => throw _privateConstructorUsedError;
  BillingFrequency get billingFrequency => throw _privateConstructorUsedError;
  List<PlanInclude> get includes => throw _privateConstructorUsedError;
  CommercialPlanStatus get status => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get createdAt => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get updatedAt => throw _privateConstructorUsedError;

  /// Serializes this CommercialPlan to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of CommercialPlan
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $CommercialPlanCopyWith<CommercialPlan> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CommercialPlanCopyWith<$Res> {
  factory $CommercialPlanCopyWith(
          CommercialPlan value, $Res Function(CommercialPlan) then) =
      _$CommercialPlanCopyWithImpl<$Res, CommercialPlan>;
  @useResult
  $Res call(
      {String id,
      String trainerId,
      String name,
      String shortDescription,
      int priceArs,
      int durationMonths,
      BillingFrequency billingFrequency,
      List<PlanInclude> includes,
      CommercialPlanStatus status,
      @TimestampConverter() DateTime createdAt,
      @TimestampConverter() DateTime updatedAt});
}

/// @nodoc
class _$CommercialPlanCopyWithImpl<$Res, $Val extends CommercialPlan>
    implements $CommercialPlanCopyWith<$Res> {
  _$CommercialPlanCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of CommercialPlan
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? trainerId = null,
    Object? name = null,
    Object? shortDescription = null,
    Object? priceArs = null,
    Object? durationMonths = null,
    Object? billingFrequency = null,
    Object? includes = null,
    Object? status = null,
    Object? createdAt = null,
    Object? updatedAt = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      trainerId: null == trainerId
          ? _value.trainerId
          : trainerId // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      shortDescription: null == shortDescription
          ? _value.shortDescription
          : shortDescription // ignore: cast_nullable_to_non_nullable
              as String,
      priceArs: null == priceArs
          ? _value.priceArs
          : priceArs // ignore: cast_nullable_to_non_nullable
              as int,
      durationMonths: null == durationMonths
          ? _value.durationMonths
          : durationMonths // ignore: cast_nullable_to_non_nullable
              as int,
      billingFrequency: null == billingFrequency
          ? _value.billingFrequency
          : billingFrequency // ignore: cast_nullable_to_non_nullable
              as BillingFrequency,
      includes: null == includes
          ? _value.includes
          : includes // ignore: cast_nullable_to_non_nullable
              as List<PlanInclude>,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as CommercialPlanStatus,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      updatedAt: null == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$CommercialPlanImplCopyWith<$Res>
    implements $CommercialPlanCopyWith<$Res> {
  factory _$$CommercialPlanImplCopyWith(_$CommercialPlanImpl value,
          $Res Function(_$CommercialPlanImpl) then) =
      __$$CommercialPlanImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String trainerId,
      String name,
      String shortDescription,
      int priceArs,
      int durationMonths,
      BillingFrequency billingFrequency,
      List<PlanInclude> includes,
      CommercialPlanStatus status,
      @TimestampConverter() DateTime createdAt,
      @TimestampConverter() DateTime updatedAt});
}

/// @nodoc
class __$$CommercialPlanImplCopyWithImpl<$Res>
    extends _$CommercialPlanCopyWithImpl<$Res, _$CommercialPlanImpl>
    implements _$$CommercialPlanImplCopyWith<$Res> {
  __$$CommercialPlanImplCopyWithImpl(
      _$CommercialPlanImpl _value, $Res Function(_$CommercialPlanImpl) _then)
      : super(_value, _then);

  /// Create a copy of CommercialPlan
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? trainerId = null,
    Object? name = null,
    Object? shortDescription = null,
    Object? priceArs = null,
    Object? durationMonths = null,
    Object? billingFrequency = null,
    Object? includes = null,
    Object? status = null,
    Object? createdAt = null,
    Object? updatedAt = null,
  }) {
    return _then(_$CommercialPlanImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      trainerId: null == trainerId
          ? _value.trainerId
          : trainerId // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      shortDescription: null == shortDescription
          ? _value.shortDescription
          : shortDescription // ignore: cast_nullable_to_non_nullable
              as String,
      priceArs: null == priceArs
          ? _value.priceArs
          : priceArs // ignore: cast_nullable_to_non_nullable
              as int,
      durationMonths: null == durationMonths
          ? _value.durationMonths
          : durationMonths // ignore: cast_nullable_to_non_nullable
              as int,
      billingFrequency: null == billingFrequency
          ? _value.billingFrequency
          : billingFrequency // ignore: cast_nullable_to_non_nullable
              as BillingFrequency,
      includes: null == includes
          ? _value._includes
          : includes // ignore: cast_nullable_to_non_nullable
              as List<PlanInclude>,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as CommercialPlanStatus,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      updatedAt: null == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$CommercialPlanImpl implements _CommercialPlan {
  const _$CommercialPlanImpl(
      {required this.id,
      required this.trainerId,
      required this.name,
      this.shortDescription = '',
      required this.priceArs,
      this.durationMonths = 1,
      this.billingFrequency = BillingFrequency.monthly,
      final List<PlanInclude> includes = const <PlanInclude>[],
      this.status = CommercialPlanStatus.active,
      @TimestampConverter() required this.createdAt,
      @TimestampConverter() required this.updatedAt})
      : _includes = includes;

  factory _$CommercialPlanImpl.fromJson(Map<String, dynamic> json) =>
      _$$CommercialPlanImplFromJson(json);

  @override
  final String id;
  @override
  final String trainerId;
  @override
  final String name;
  @override
  @JsonKey()
  final String shortDescription;
  @override
  final int priceArs;
  @override
  @JsonKey()
  final int durationMonths;
  @override
  @JsonKey()
  final BillingFrequency billingFrequency;
  final List<PlanInclude> _includes;
  @override
  @JsonKey()
  List<PlanInclude> get includes {
    if (_includes is EqualUnmodifiableListView) return _includes;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_includes);
  }

  @override
  @JsonKey()
  final CommercialPlanStatus status;
  @override
  @TimestampConverter()
  final DateTime createdAt;
  @override
  @TimestampConverter()
  final DateTime updatedAt;

  @override
  String toString() {
    return 'CommercialPlan(id: $id, trainerId: $trainerId, name: $name, shortDescription: $shortDescription, priceArs: $priceArs, durationMonths: $durationMonths, billingFrequency: $billingFrequency, includes: $includes, status: $status, createdAt: $createdAt, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CommercialPlanImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.trainerId, trainerId) ||
                other.trainerId == trainerId) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.shortDescription, shortDescription) ||
                other.shortDescription == shortDescription) &&
            (identical(other.priceArs, priceArs) ||
                other.priceArs == priceArs) &&
            (identical(other.durationMonths, durationMonths) ||
                other.durationMonths == durationMonths) &&
            (identical(other.billingFrequency, billingFrequency) ||
                other.billingFrequency == billingFrequency) &&
            const DeepCollectionEquality().equals(other._includes, _includes) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      trainerId,
      name,
      shortDescription,
      priceArs,
      durationMonths,
      billingFrequency,
      const DeepCollectionEquality().hash(_includes),
      status,
      createdAt,
      updatedAt);

  /// Create a copy of CommercialPlan
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$CommercialPlanImplCopyWith<_$CommercialPlanImpl> get copyWith =>
      __$$CommercialPlanImplCopyWithImpl<_$CommercialPlanImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$CommercialPlanImplToJson(
      this,
    );
  }
}

abstract class _CommercialPlan implements CommercialPlan {
  const factory _CommercialPlan(
          {required final String id,
          required final String trainerId,
          required final String name,
          final String shortDescription,
          required final int priceArs,
          final int durationMonths,
          final BillingFrequency billingFrequency,
          final List<PlanInclude> includes,
          final CommercialPlanStatus status,
          @TimestampConverter() required final DateTime createdAt,
          @TimestampConverter() required final DateTime updatedAt}) =
      _$CommercialPlanImpl;

  factory _CommercialPlan.fromJson(Map<String, dynamic> json) =
      _$CommercialPlanImpl.fromJson;

  @override
  String get id;
  @override
  String get trainerId;
  @override
  String get name;
  @override
  String get shortDescription;
  @override
  int get priceArs;
  @override
  int get durationMonths;
  @override
  BillingFrequency get billingFrequency;
  @override
  List<PlanInclude> get includes;
  @override
  CommercialPlanStatus get status;
  @override
  @TimestampConverter()
  DateTime get createdAt;
  @override
  @TimestampConverter()
  DateTime get updatedAt;

  /// Create a copy of CommercialPlan
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$CommercialPlanImplCopyWith<_$CommercialPlanImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
