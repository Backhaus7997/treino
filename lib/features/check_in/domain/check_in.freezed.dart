// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'check_in.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

CheckIn _$CheckInFromJson(Map<String, dynamic> json) {
  return _CheckIn.fromJson(json);
}

/// @nodoc
mixin _$CheckIn {
  String get uid => throw _privateConstructorUsedError;

  /// 'YYYY-MM-DD' in user local time. Also the Firestore doc id → natural dedup.
  String get date => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get checkedInAt => throw _privateConstructorUsedError;
  String? get gymId => throw _privateConstructorUsedError;
  String? get gymName => throw _privateConstructorUsedError;

  /// Serializes this CheckIn to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of CheckIn
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $CheckInCopyWith<CheckIn> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CheckInCopyWith<$Res> {
  factory $CheckInCopyWith(CheckIn value, $Res Function(CheckIn) then) =
      _$CheckInCopyWithImpl<$Res, CheckIn>;
  @useResult
  $Res call(
      {String uid,
      String date,
      @TimestampConverter() DateTime checkedInAt,
      String? gymId,
      String? gymName});
}

/// @nodoc
class _$CheckInCopyWithImpl<$Res, $Val extends CheckIn>
    implements $CheckInCopyWith<$Res> {
  _$CheckInCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of CheckIn
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? uid = null,
    Object? date = null,
    Object? checkedInAt = null,
    Object? gymId = freezed,
    Object? gymName = freezed,
  }) {
    return _then(_value.copyWith(
      uid: null == uid
          ? _value.uid
          : uid // ignore: cast_nullable_to_non_nullable
              as String,
      date: null == date
          ? _value.date
          : date // ignore: cast_nullable_to_non_nullable
              as String,
      checkedInAt: null == checkedInAt
          ? _value.checkedInAt
          : checkedInAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      gymId: freezed == gymId
          ? _value.gymId
          : gymId // ignore: cast_nullable_to_non_nullable
              as String?,
      gymName: freezed == gymName
          ? _value.gymName
          : gymName // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$CheckInImplCopyWith<$Res> implements $CheckInCopyWith<$Res> {
  factory _$$CheckInImplCopyWith(
          _$CheckInImpl value, $Res Function(_$CheckInImpl) then) =
      __$$CheckInImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String uid,
      String date,
      @TimestampConverter() DateTime checkedInAt,
      String? gymId,
      String? gymName});
}

/// @nodoc
class __$$CheckInImplCopyWithImpl<$Res>
    extends _$CheckInCopyWithImpl<$Res, _$CheckInImpl>
    implements _$$CheckInImplCopyWith<$Res> {
  __$$CheckInImplCopyWithImpl(
      _$CheckInImpl _value, $Res Function(_$CheckInImpl) _then)
      : super(_value, _then);

  /// Create a copy of CheckIn
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? uid = null,
    Object? date = null,
    Object? checkedInAt = null,
    Object? gymId = freezed,
    Object? gymName = freezed,
  }) {
    return _then(_$CheckInImpl(
      uid: null == uid
          ? _value.uid
          : uid // ignore: cast_nullable_to_non_nullable
              as String,
      date: null == date
          ? _value.date
          : date // ignore: cast_nullable_to_non_nullable
              as String,
      checkedInAt: null == checkedInAt
          ? _value.checkedInAt
          : checkedInAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      gymId: freezed == gymId
          ? _value.gymId
          : gymId // ignore: cast_nullable_to_non_nullable
              as String?,
      gymName: freezed == gymName
          ? _value.gymName
          : gymName // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$CheckInImpl implements _CheckIn {
  const _$CheckInImpl(
      {required this.uid,
      required this.date,
      @TimestampConverter() required this.checkedInAt,
      this.gymId,
      this.gymName});

  factory _$CheckInImpl.fromJson(Map<String, dynamic> json) =>
      _$$CheckInImplFromJson(json);

  @override
  final String uid;

  /// 'YYYY-MM-DD' in user local time. Also the Firestore doc id → natural dedup.
  @override
  final String date;
  @override
  @TimestampConverter()
  final DateTime checkedInAt;
  @override
  final String? gymId;
  @override
  final String? gymName;

  @override
  String toString() {
    return 'CheckIn(uid: $uid, date: $date, checkedInAt: $checkedInAt, gymId: $gymId, gymName: $gymName)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CheckInImpl &&
            (identical(other.uid, uid) || other.uid == uid) &&
            (identical(other.date, date) || other.date == date) &&
            (identical(other.checkedInAt, checkedInAt) ||
                other.checkedInAt == checkedInAt) &&
            (identical(other.gymId, gymId) || other.gymId == gymId) &&
            (identical(other.gymName, gymName) || other.gymName == gymName));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, uid, date, checkedInAt, gymId, gymName);

  /// Create a copy of CheckIn
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$CheckInImplCopyWith<_$CheckInImpl> get copyWith =>
      __$$CheckInImplCopyWithImpl<_$CheckInImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$CheckInImplToJson(
      this,
    );
  }
}

abstract class _CheckIn implements CheckIn {
  const factory _CheckIn(
      {required final String uid,
      required final String date,
      @TimestampConverter() required final DateTime checkedInAt,
      final String? gymId,
      final String? gymName}) = _$CheckInImpl;

  factory _CheckIn.fromJson(Map<String, dynamic> json) = _$CheckInImpl.fromJson;

  @override
  String get uid;

  /// 'YYYY-MM-DD' in user local time. Also the Firestore doc id → natural dedup.
  @override
  String get date;
  @override
  @TimestampConverter()
  DateTime get checkedInAt;
  @override
  String? get gymId;
  @override
  String? get gymName;

  /// Create a copy of CheckIn
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$CheckInImplCopyWith<_$CheckInImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
