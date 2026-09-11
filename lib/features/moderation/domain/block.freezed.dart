// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'block.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Block _$BlockFromJson(Map<String, dynamic> json) {
  return _Block.fromJson(json);
}

/// @nodoc
mixin _$Block {
  @JsonKey(includeToJson: false)
  String get id => throw _privateConstructorUsedError;
  String get blockerUid => throw _privateConstructorUsedError;
  String get blockedUid => throw _privateConstructorUsedError;
  List<String> get members => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get createdAt => throw _privateConstructorUsedError;

  /// Serializes this Block to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Block
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $BlockCopyWith<Block> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BlockCopyWith<$Res> {
  factory $BlockCopyWith(Block value, $Res Function(Block) then) =
      _$BlockCopyWithImpl<$Res, Block>;
  @useResult
  $Res call(
      {@JsonKey(includeToJson: false) String id,
      String blockerUid,
      String blockedUid,
      List<String> members,
      @TimestampConverter() DateTime createdAt});
}

/// @nodoc
class _$BlockCopyWithImpl<$Res, $Val extends Block>
    implements $BlockCopyWith<$Res> {
  _$BlockCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Block
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? blockerUid = null,
    Object? blockedUid = null,
    Object? members = null,
    Object? createdAt = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      blockerUid: null == blockerUid
          ? _value.blockerUid
          : blockerUid // ignore: cast_nullable_to_non_nullable
              as String,
      blockedUid: null == blockedUid
          ? _value.blockedUid
          : blockedUid // ignore: cast_nullable_to_non_nullable
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
abstract class _$$BlockImplCopyWith<$Res> implements $BlockCopyWith<$Res> {
  factory _$$BlockImplCopyWith(
          _$BlockImpl value, $Res Function(_$BlockImpl) then) =
      __$$BlockImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(includeToJson: false) String id,
      String blockerUid,
      String blockedUid,
      List<String> members,
      @TimestampConverter() DateTime createdAt});
}

/// @nodoc
class __$$BlockImplCopyWithImpl<$Res>
    extends _$BlockCopyWithImpl<$Res, _$BlockImpl>
    implements _$$BlockImplCopyWith<$Res> {
  __$$BlockImplCopyWithImpl(
      _$BlockImpl _value, $Res Function(_$BlockImpl) _then)
      : super(_value, _then);

  /// Create a copy of Block
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? blockerUid = null,
    Object? blockedUid = null,
    Object? members = null,
    Object? createdAt = null,
  }) {
    return _then(_$BlockImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      blockerUid: null == blockerUid
          ? _value.blockerUid
          : blockerUid // ignore: cast_nullable_to_non_nullable
              as String,
      blockedUid: null == blockedUid
          ? _value.blockedUid
          : blockedUid // ignore: cast_nullable_to_non_nullable
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
class _$BlockImpl extends _Block {
  const _$BlockImpl(
      {@JsonKey(includeToJson: false) required this.id,
      required this.blockerUid,
      required this.blockedUid,
      required final List<String> members,
      @TimestampConverter() required this.createdAt})
      : _members = members,
        super._();

  factory _$BlockImpl.fromJson(Map<String, dynamic> json) =>
      _$$BlockImplFromJson(json);

  @override
  @JsonKey(includeToJson: false)
  final String id;
  @override
  final String blockerUid;
  @override
  final String blockedUid;
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
    return 'Block(id: $id, blockerUid: $blockerUid, blockedUid: $blockedUid, members: $members, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BlockImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.blockerUid, blockerUid) ||
                other.blockerUid == blockerUid) &&
            (identical(other.blockedUid, blockedUid) ||
                other.blockedUid == blockedUid) &&
            const DeepCollectionEquality().equals(other._members, _members) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, blockerUid, blockedUid,
      const DeepCollectionEquality().hash(_members), createdAt);

  /// Create a copy of Block
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$BlockImplCopyWith<_$BlockImpl> get copyWith =>
      __$$BlockImplCopyWithImpl<_$BlockImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$BlockImplToJson(
      this,
    );
  }
}

abstract class _Block extends Block {
  const factory _Block(
      {@JsonKey(includeToJson: false) required final String id,
      required final String blockerUid,
      required final String blockedUid,
      required final List<String> members,
      @TimestampConverter() required final DateTime createdAt}) = _$BlockImpl;
  const _Block._() : super._();

  factory _Block.fromJson(Map<String, dynamic> json) = _$BlockImpl.fromJson;

  @override
  @JsonKey(includeToJson: false)
  String get id;
  @override
  String get blockerUid;
  @override
  String get blockedUid;
  @override
  List<String> get members;
  @override
  @TimestampConverter()
  DateTime get createdAt;

  /// Create a copy of Block
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$BlockImplCopyWith<_$BlockImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
