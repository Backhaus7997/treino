// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'friendship.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Friendship _$FriendshipFromJson(Map<String, dynamic> json) {
  return _Friendship.fromJson(json);
}

/// @nodoc
mixin _$Friendship {
  String get id => throw _privateConstructorUsedError;
  String get uidA => throw _privateConstructorUsedError;
  String get uidB => throw _privateConstructorUsedError;
  FriendshipStatus get status => throw _privateConstructorUsedError;
  String get requesterId => throw _privateConstructorUsedError;
  List<String> get members => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get createdAt => throw _privateConstructorUsedError;

  /// Serializes this Friendship to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Friendship
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $FriendshipCopyWith<Friendship> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $FriendshipCopyWith<$Res> {
  factory $FriendshipCopyWith(
          Friendship value, $Res Function(Friendship) then) =
      _$FriendshipCopyWithImpl<$Res, Friendship>;
  @useResult
  $Res call(
      {String id,
      String uidA,
      String uidB,
      FriendshipStatus status,
      String requesterId,
      List<String> members,
      @TimestampConverter() DateTime createdAt});
}

/// @nodoc
class _$FriendshipCopyWithImpl<$Res, $Val extends Friendship>
    implements $FriendshipCopyWith<$Res> {
  _$FriendshipCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Friendship
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? uidA = null,
    Object? uidB = null,
    Object? status = null,
    Object? requesterId = null,
    Object? members = null,
    Object? createdAt = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      uidA: null == uidA
          ? _value.uidA
          : uidA // ignore: cast_nullable_to_non_nullable
              as String,
      uidB: null == uidB
          ? _value.uidB
          : uidB // ignore: cast_nullable_to_non_nullable
              as String,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as FriendshipStatus,
      requesterId: null == requesterId
          ? _value.requesterId
          : requesterId // ignore: cast_nullable_to_non_nullable
              as String,
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
abstract class _$$FriendshipImplCopyWith<$Res>
    implements $FriendshipCopyWith<$Res> {
  factory _$$FriendshipImplCopyWith(
          _$FriendshipImpl value, $Res Function(_$FriendshipImpl) then) =
      __$$FriendshipImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String uidA,
      String uidB,
      FriendshipStatus status,
      String requesterId,
      List<String> members,
      @TimestampConverter() DateTime createdAt});
}

/// @nodoc
class __$$FriendshipImplCopyWithImpl<$Res>
    extends _$FriendshipCopyWithImpl<$Res, _$FriendshipImpl>
    implements _$$FriendshipImplCopyWith<$Res> {
  __$$FriendshipImplCopyWithImpl(
      _$FriendshipImpl _value, $Res Function(_$FriendshipImpl) _then)
      : super(_value, _then);

  /// Create a copy of Friendship
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? uidA = null,
    Object? uidB = null,
    Object? status = null,
    Object? requesterId = null,
    Object? members = null,
    Object? createdAt = null,
  }) {
    return _then(_$FriendshipImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      uidA: null == uidA
          ? _value.uidA
          : uidA // ignore: cast_nullable_to_non_nullable
              as String,
      uidB: null == uidB
          ? _value.uidB
          : uidB // ignore: cast_nullable_to_non_nullable
              as String,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as FriendshipStatus,
      requesterId: null == requesterId
          ? _value.requesterId
          : requesterId // ignore: cast_nullable_to_non_nullable
              as String,
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
class _$FriendshipImpl extends _Friendship {
  const _$FriendshipImpl(
      {required this.id,
      required this.uidA,
      required this.uidB,
      required this.status,
      required this.requesterId,
      required final List<String> members,
      @TimestampConverter() required this.createdAt})
      : _members = members,
        super._();

  factory _$FriendshipImpl.fromJson(Map<String, dynamic> json) =>
      _$$FriendshipImplFromJson(json);

  @override
  final String id;
  @override
  final String uidA;
  @override
  final String uidB;
  @override
  final FriendshipStatus status;
  @override
  final String requesterId;
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
    return 'Friendship(id: $id, uidA: $uidA, uidB: $uidB, status: $status, requesterId: $requesterId, members: $members, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FriendshipImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.uidA, uidA) || other.uidA == uidA) &&
            (identical(other.uidB, uidB) || other.uidB == uidB) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.requesterId, requesterId) ||
                other.requesterId == requesterId) &&
            const DeepCollectionEquality().equals(other._members, _members) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, uidA, uidB, status,
      requesterId, const DeepCollectionEquality().hash(_members), createdAt);

  /// Create a copy of Friendship
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$FriendshipImplCopyWith<_$FriendshipImpl> get copyWith =>
      __$$FriendshipImplCopyWithImpl<_$FriendshipImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$FriendshipImplToJson(
      this,
    );
  }
}

abstract class _Friendship extends Friendship {
  const factory _Friendship(
          {required final String id,
          required final String uidA,
          required final String uidB,
          required final FriendshipStatus status,
          required final String requesterId,
          required final List<String> members,
          @TimestampConverter() required final DateTime createdAt}) =
      _$FriendshipImpl;
  const _Friendship._() : super._();

  factory _Friendship.fromJson(Map<String, dynamic> json) =
      _$FriendshipImpl.fromJson;

  @override
  String get id;
  @override
  String get uidA;
  @override
  String get uidB;
  @override
  FriendshipStatus get status;
  @override
  String get requesterId;
  @override
  List<String> get members;
  @override
  @TimestampConverter()
  DateTime get createdAt;

  /// Create a copy of Friendship
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$FriendshipImplCopyWith<_$FriendshipImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
