// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'trainer_link.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

TrainerLink _$TrainerLinkFromJson(Map<String, dynamic> json) {
  return _TrainerLink.fromJson(json);
}

/// @nodoc
mixin _$TrainerLink {
  String get id => throw _privateConstructorUsedError;
  String get trainerId => throw _privateConstructorUsedError;
  String get athleteId => throw _privateConstructorUsedError;
  TrainerLinkStatus get status => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get requestedAt => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime? get acceptedAt => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime? get terminatedAt => throw _privateConstructorUsedError;
  String? get terminationReason => throw _privateConstructorUsedError;

  /// Serializes this TrainerLink to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of TrainerLink
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $TrainerLinkCopyWith<TrainerLink> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TrainerLinkCopyWith<$Res> {
  factory $TrainerLinkCopyWith(
          TrainerLink value, $Res Function(TrainerLink) then) =
      _$TrainerLinkCopyWithImpl<$Res, TrainerLink>;
  @useResult
  $Res call(
      {String id,
      String trainerId,
      String athleteId,
      TrainerLinkStatus status,
      @TimestampConverter() DateTime requestedAt,
      @TimestampConverter() DateTime? acceptedAt,
      @TimestampConverter() DateTime? terminatedAt,
      String? terminationReason});
}

/// @nodoc
class _$TrainerLinkCopyWithImpl<$Res, $Val extends TrainerLink>
    implements $TrainerLinkCopyWith<$Res> {
  _$TrainerLinkCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of TrainerLink
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? trainerId = null,
    Object? athleteId = null,
    Object? status = null,
    Object? requestedAt = null,
    Object? acceptedAt = freezed,
    Object? terminatedAt = freezed,
    Object? terminationReason = freezed,
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
      athleteId: null == athleteId
          ? _value.athleteId
          : athleteId // ignore: cast_nullable_to_non_nullable
              as String,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as TrainerLinkStatus,
      requestedAt: null == requestedAt
          ? _value.requestedAt
          : requestedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      acceptedAt: freezed == acceptedAt
          ? _value.acceptedAt
          : acceptedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      terminatedAt: freezed == terminatedAt
          ? _value.terminatedAt
          : terminatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      terminationReason: freezed == terminationReason
          ? _value.terminationReason
          : terminationReason // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$TrainerLinkImplCopyWith<$Res>
    implements $TrainerLinkCopyWith<$Res> {
  factory _$$TrainerLinkImplCopyWith(
          _$TrainerLinkImpl value, $Res Function(_$TrainerLinkImpl) then) =
      __$$TrainerLinkImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String trainerId,
      String athleteId,
      TrainerLinkStatus status,
      @TimestampConverter() DateTime requestedAt,
      @TimestampConverter() DateTime? acceptedAt,
      @TimestampConverter() DateTime? terminatedAt,
      String? terminationReason});
}

/// @nodoc
class __$$TrainerLinkImplCopyWithImpl<$Res>
    extends _$TrainerLinkCopyWithImpl<$Res, _$TrainerLinkImpl>
    implements _$$TrainerLinkImplCopyWith<$Res> {
  __$$TrainerLinkImplCopyWithImpl(
      _$TrainerLinkImpl _value, $Res Function(_$TrainerLinkImpl) _then)
      : super(_value, _then);

  /// Create a copy of TrainerLink
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? trainerId = null,
    Object? athleteId = null,
    Object? status = null,
    Object? requestedAt = null,
    Object? acceptedAt = freezed,
    Object? terminatedAt = freezed,
    Object? terminationReason = freezed,
  }) {
    return _then(_$TrainerLinkImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      trainerId: null == trainerId
          ? _value.trainerId
          : trainerId // ignore: cast_nullable_to_non_nullable
              as String,
      athleteId: null == athleteId
          ? _value.athleteId
          : athleteId // ignore: cast_nullable_to_non_nullable
              as String,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as TrainerLinkStatus,
      requestedAt: null == requestedAt
          ? _value.requestedAt
          : requestedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      acceptedAt: freezed == acceptedAt
          ? _value.acceptedAt
          : acceptedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      terminatedAt: freezed == terminatedAt
          ? _value.terminatedAt
          : terminatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      terminationReason: freezed == terminationReason
          ? _value.terminationReason
          : terminationReason // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$TrainerLinkImpl implements _TrainerLink {
  const _$TrainerLinkImpl(
      {required this.id,
      required this.trainerId,
      required this.athleteId,
      required this.status,
      @TimestampConverter() required this.requestedAt,
      @TimestampConverter() this.acceptedAt,
      @TimestampConverter() this.terminatedAt,
      this.terminationReason});

  factory _$TrainerLinkImpl.fromJson(Map<String, dynamic> json) =>
      _$$TrainerLinkImplFromJson(json);

  @override
  final String id;
  @override
  final String trainerId;
  @override
  final String athleteId;
  @override
  final TrainerLinkStatus status;
  @override
  @TimestampConverter()
  final DateTime requestedAt;
  @override
  @TimestampConverter()
  final DateTime? acceptedAt;
  @override
  @TimestampConverter()
  final DateTime? terminatedAt;
  @override
  final String? terminationReason;

  @override
  String toString() {
    return 'TrainerLink(id: $id, trainerId: $trainerId, athleteId: $athleteId, status: $status, requestedAt: $requestedAt, acceptedAt: $acceptedAt, terminatedAt: $terminatedAt, terminationReason: $terminationReason)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TrainerLinkImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.trainerId, trainerId) ||
                other.trainerId == trainerId) &&
            (identical(other.athleteId, athleteId) ||
                other.athleteId == athleteId) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.requestedAt, requestedAt) ||
                other.requestedAt == requestedAt) &&
            (identical(other.acceptedAt, acceptedAt) ||
                other.acceptedAt == acceptedAt) &&
            (identical(other.terminatedAt, terminatedAt) ||
                other.terminatedAt == terminatedAt) &&
            (identical(other.terminationReason, terminationReason) ||
                other.terminationReason == terminationReason));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, trainerId, athleteId, status,
      requestedAt, acceptedAt, terminatedAt, terminationReason);

  /// Create a copy of TrainerLink
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TrainerLinkImplCopyWith<_$TrainerLinkImpl> get copyWith =>
      __$$TrainerLinkImplCopyWithImpl<_$TrainerLinkImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$TrainerLinkImplToJson(
      this,
    );
  }
}

abstract class _TrainerLink implements TrainerLink {
  const factory _TrainerLink(
      {required final String id,
      required final String trainerId,
      required final String athleteId,
      required final TrainerLinkStatus status,
      @TimestampConverter() required final DateTime requestedAt,
      @TimestampConverter() final DateTime? acceptedAt,
      @TimestampConverter() final DateTime? terminatedAt,
      final String? terminationReason}) = _$TrainerLinkImpl;

  factory _TrainerLink.fromJson(Map<String, dynamic> json) =
      _$TrainerLinkImpl.fromJson;

  @override
  String get id;
  @override
  String get trainerId;
  @override
  String get athleteId;
  @override
  TrainerLinkStatus get status;
  @override
  @TimestampConverter()
  DateTime get requestedAt;
  @override
  @TimestampConverter()
  DateTime? get acceptedAt;
  @override
  @TimestampConverter()
  DateTime? get terminatedAt;
  @override
  String? get terminationReason;

  /// Create a copy of TrainerLink
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TrainerLinkImplCopyWith<_$TrainerLinkImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
