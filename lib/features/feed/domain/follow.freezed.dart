// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'follow.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Follow _$FollowFromJson(Map<String, dynamic> json) {
  return _Follow.fromJson(json);
}

/// @nodoc
mixin _$Follow {
  String get id => throw _privateConstructorUsedError;
  String get followerUid => throw _privateConstructorUsedError;
  String get followeeUid => throw _privateConstructorUsedError;
  FollowStatus get status => throw _privateConstructorUsedError;
  List<String> get members => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get createdAt => throw _privateConstructorUsedError;

  /// Serializes this Follow to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Follow
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $FollowCopyWith<Follow> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $FollowCopyWith<$Res> {
  factory $FollowCopyWith(Follow value, $Res Function(Follow) then) =
      _$FollowCopyWithImpl<$Res, Follow>;
  @useResult
  $Res call(
      {String id,
      String followerUid,
      String followeeUid,
      FollowStatus status,
      List<String> members,
      @TimestampConverter() DateTime createdAt});
}

/// @nodoc
class _$FollowCopyWithImpl<$Res, $Val extends Follow>
    implements $FollowCopyWith<$Res> {
  _$FollowCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Follow
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? followerUid = null,
    Object? followeeUid = null,
    Object? status = null,
    Object? members = null,
    Object? createdAt = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      followerUid: null == followerUid
          ? _value.followerUid
          : followerUid // ignore: cast_nullable_to_non_nullable
              as String,
      followeeUid: null == followeeUid
          ? _value.followeeUid
          : followeeUid // ignore: cast_nullable_to_non_nullable
              as String,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as FollowStatus,
      members: null == members
          ? _value.members
          : members // ignore: cast_nullable_to_non_nullable
              as List<String>,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$FollowImplCopyWith<$Res> implements $FollowCopyWith<$Res> {
  factory _$$FollowImplCopyWith(
          _$FollowImpl value, $Res Function(_$FollowImpl) then) =
      __$$FollowImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String followerUid,
      String followeeUid,
      FollowStatus status,
      List<String> members,
      @TimestampConverter() DateTime createdAt});
}

/// @nodoc
class __$$FollowImplCopyWithImpl<$Res>
    extends _$FollowCopyWithImpl<$Res, _$FollowImpl>
    implements _$$FollowImplCopyWith<$Res> {
  __$$FollowImplCopyWithImpl(
      _$FollowImpl _value, $Res Function(_$FollowImpl) _then)
      : super(_value, _then);

  /// Create a copy of Follow
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? followerUid = null,
    Object? followeeUid = null,
    Object? status = null,
    Object? members = null,
    Object? createdAt = null,
  }) {
    return _then(_$FollowImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      followerUid: null == followerUid
          ? _value.followerUid
          : followerUid // ignore: cast_nullable_to_non_nullable
              as String,
      followeeUid: null == followeeUid
          ? _value.followeeUid
          : followeeUid // ignore: cast_nullable_to_non_nullable
              as String,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as FollowStatus,
      members: null == members
          ? _value._members
          : members // ignore: cast_nullable_to_non_nullable
              as List<String>,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$FollowImpl extends _Follow {
  const _$FollowImpl(
      {required this.id,
      required this.followerUid,
      required this.followeeUid,
      required this.status,
      required final List<String> members,
      @TimestampConverter() required this.createdAt})
      : _members = members,
        super._();

  factory _$FollowImpl.fromJson(Map<String, dynamic> json) =>
      _$$FollowImplFromJson(json);

  @override
  final String id;
  @override
  final String followerUid;
  @override
  final String followeeUid;
  @override
  final FollowStatus status;
  final List<String> _members;
  @override
  List<String> get members {
    if (_members is EqualUnmodifiableListView) return _members;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_members);
  }

  @override
  @TimestampConverter()
  final DateTime createdAt;

  @override
  String toString() {
    return 'Follow(id: $id, followerUid: $followerUid, followeeUid: $followeeUid, status: $status, members: $members, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FollowImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.followerUid, followerUid) ||
                other.followerUid == followerUid) &&
            (identical(other.followeeUid, followeeUid) ||
                other.followeeUid == followeeUid) &&
            (identical(other.status, status) || other.status == status) &&
            const DeepCollectionEquality().equals(other._members, _members) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, followerUid, followeeUid,
      status, const DeepCollectionEquality().hash(_members), createdAt);

  /// Create a copy of Follow
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$FollowImplCopyWith<_$FollowImpl> get copyWith =>
      __$$FollowImplCopyWithImpl<_$FollowImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$FollowImplToJson(
      this,
    );
  }
}

abstract class _Follow extends Follow {
  const factory _Follow(
      {required final String id,
      required final String followerUid,
      required final String followeeUid,
      required final FollowStatus status,
      required final List<String> members,
      @TimestampConverter() required final DateTime createdAt}) = _$FollowImpl;
  const _Follow._() : super._();

  factory _Follow.fromJson(Map<String, dynamic> json) = _$FollowImpl.fromJson;

  @override
  String get id;
  @override
  String get followerUid;
  @override
  String get followeeUid;
  @override
  FollowStatus get status;
  @override
  List<String> get members;
  @override
  @TimestampConverter()
  DateTime get createdAt;

  /// Create a copy of Follow
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$FollowImplCopyWith<_$FollowImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
