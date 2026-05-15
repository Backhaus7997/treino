// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'post.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Post _$PostFromJson(Map<String, dynamic> json) {
  return _Post.fromJson(json);
}

/// @nodoc
mixin _$Post {
  String get id => throw _privateConstructorUsedError;
  String get authorUid =>
      throw _privateConstructorUsedError; // Author display fields denormalized at write time (same ADR as authorGymId).
// Stale-on-update is accepted — standard social-media pattern.
// `@Default('Anónimo')` handles legacy Firestore docs that predate this field —
// json_serializable applies the default when the JSON key is missing.
  String get authorDisplayName => throw _privateConstructorUsedError;
  String? get authorAvatarUrl => throw _privateConstructorUsedError;
  String? get authorGymId => throw _privateConstructorUsedError;
  String get text => throw _privateConstructorUsedError;
  RoutineTag? get routineTag => throw _privateConstructorUsedError;
  PostPrivacy get privacy => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get createdAt => throw _privateConstructorUsedError;

  /// Serializes this Post to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Post
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PostCopyWith<Post> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PostCopyWith<$Res> {
  factory $PostCopyWith(Post value, $Res Function(Post) then) =
      _$PostCopyWithImpl<$Res, Post>;
  @useResult
  $Res call(
      {String id,
      String authorUid,
      String authorDisplayName,
      String? authorAvatarUrl,
      String? authorGymId,
      String text,
      RoutineTag? routineTag,
      PostPrivacy privacy,
      @TimestampConverter() DateTime createdAt});

  $RoutineTagCopyWith<$Res>? get routineTag;
}

/// @nodoc
class _$PostCopyWithImpl<$Res, $Val extends Post>
    implements $PostCopyWith<$Res> {
  _$PostCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Post
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? authorUid = null,
    Object? authorDisplayName = null,
    Object? authorAvatarUrl = freezed,
    Object? authorGymId = freezed,
    Object? text = null,
    Object? routineTag = freezed,
    Object? privacy = null,
    Object? createdAt = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      authorUid: null == authorUid
          ? _value.authorUid
          : authorUid // ignore: cast_nullable_to_non_nullable
              as String,
      authorDisplayName: null == authorDisplayName
          ? _value.authorDisplayName
          : authorDisplayName // ignore: cast_nullable_to_non_nullable
              as String,
      authorAvatarUrl: freezed == authorAvatarUrl
          ? _value.authorAvatarUrl
          : authorAvatarUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      authorGymId: freezed == authorGymId
          ? _value.authorGymId
          : authorGymId // ignore: cast_nullable_to_non_nullable
              as String?,
      text: null == text
          ? _value.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
      routineTag: freezed == routineTag
          ? _value.routineTag
          : routineTag // ignore: cast_nullable_to_non_nullable
              as RoutineTag?,
      privacy: null == privacy
          ? _value.privacy
          : privacy // ignore: cast_nullable_to_non_nullable
              as PostPrivacy,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }

  /// Create a copy of Post
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $RoutineTagCopyWith<$Res>? get routineTag {
    if (_value.routineTag == null) {
      return null;
    }

    return $RoutineTagCopyWith<$Res>(_value.routineTag!, (value) {
      return _then(_value.copyWith(routineTag: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$PostImplCopyWith<$Res> implements $PostCopyWith<$Res> {
  factory _$$PostImplCopyWith(
          _$PostImpl value, $Res Function(_$PostImpl) then) =
      __$$PostImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String authorUid,
      String authorDisplayName,
      String? authorAvatarUrl,
      String? authorGymId,
      String text,
      RoutineTag? routineTag,
      PostPrivacy privacy,
      @TimestampConverter() DateTime createdAt});

  @override
  $RoutineTagCopyWith<$Res>? get routineTag;
}

/// @nodoc
class __$$PostImplCopyWithImpl<$Res>
    extends _$PostCopyWithImpl<$Res, _$PostImpl>
    implements _$$PostImplCopyWith<$Res> {
  __$$PostImplCopyWithImpl(_$PostImpl _value, $Res Function(_$PostImpl) _then)
      : super(_value, _then);

  /// Create a copy of Post
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? authorUid = null,
    Object? authorDisplayName = null,
    Object? authorAvatarUrl = freezed,
    Object? authorGymId = freezed,
    Object? text = null,
    Object? routineTag = freezed,
    Object? privacy = null,
    Object? createdAt = null,
  }) {
    return _then(_$PostImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      authorUid: null == authorUid
          ? _value.authorUid
          : authorUid // ignore: cast_nullable_to_non_nullable
              as String,
      authorDisplayName: null == authorDisplayName
          ? _value.authorDisplayName
          : authorDisplayName // ignore: cast_nullable_to_non_nullable
              as String,
      authorAvatarUrl: freezed == authorAvatarUrl
          ? _value.authorAvatarUrl
          : authorAvatarUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      authorGymId: freezed == authorGymId
          ? _value.authorGymId
          : authorGymId // ignore: cast_nullable_to_non_nullable
              as String?,
      text: null == text
          ? _value.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
      routineTag: freezed == routineTag
          ? _value.routineTag
          : routineTag // ignore: cast_nullable_to_non_nullable
              as RoutineTag?,
      privacy: null == privacy
          ? _value.privacy
          : privacy // ignore: cast_nullable_to_non_nullable
              as PostPrivacy,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$PostImpl implements _Post {
  const _$PostImpl(
      {required this.id,
      required this.authorUid,
      this.authorDisplayName = 'Anónimo',
      required this.authorAvatarUrl,
      required this.authorGymId,
      required this.text,
      required this.routineTag,
      required this.privacy,
      @TimestampConverter() required this.createdAt});

  factory _$PostImpl.fromJson(Map<String, dynamic> json) =>
      _$$PostImplFromJson(json);

  @override
  final String id;
  @override
  final String authorUid;
// Author display fields denormalized at write time (same ADR as authorGymId).
// Stale-on-update is accepted — standard social-media pattern.
// `@Default('Anónimo')` handles legacy Firestore docs that predate this field —
// json_serializable applies the default when the JSON key is missing.
  @override
  @JsonKey()
  final String authorDisplayName;
  @override
  final String? authorAvatarUrl;
  @override
  final String? authorGymId;
  @override
  final String text;
  @override
  final RoutineTag? routineTag;
  @override
  final PostPrivacy privacy;
  @override
  @TimestampConverter()
  final DateTime createdAt;

  @override
  String toString() {
    return 'Post(id: $id, authorUid: $authorUid, authorDisplayName: $authorDisplayName, authorAvatarUrl: $authorAvatarUrl, authorGymId: $authorGymId, text: $text, routineTag: $routineTag, privacy: $privacy, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PostImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.authorUid, authorUid) ||
                other.authorUid == authorUid) &&
            (identical(other.authorDisplayName, authorDisplayName) ||
                other.authorDisplayName == authorDisplayName) &&
            (identical(other.authorAvatarUrl, authorAvatarUrl) ||
                other.authorAvatarUrl == authorAvatarUrl) &&
            (identical(other.authorGymId, authorGymId) ||
                other.authorGymId == authorGymId) &&
            (identical(other.text, text) || other.text == text) &&
            (identical(other.routineTag, routineTag) ||
                other.routineTag == routineTag) &&
            (identical(other.privacy, privacy) || other.privacy == privacy) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, authorUid, authorDisplayName,
      authorAvatarUrl, authorGymId, text, routineTag, privacy, createdAt);

  /// Create a copy of Post
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PostImplCopyWith<_$PostImpl> get copyWith =>
      __$$PostImplCopyWithImpl<_$PostImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PostImplToJson(
      this,
    );
  }
}

abstract class _Post implements Post {
  const factory _Post(
      {required final String id,
      required final String authorUid,
      final String authorDisplayName,
      required final String? authorAvatarUrl,
      required final String? authorGymId,
      required final String text,
      required final RoutineTag? routineTag,
      required final PostPrivacy privacy,
      @TimestampConverter() required final DateTime createdAt}) = _$PostImpl;

  factory _Post.fromJson(Map<String, dynamic> json) = _$PostImpl.fromJson;

  @override
  String get id;
  @override
  String
      get authorUid; // Author display fields denormalized at write time (same ADR as authorGymId).
// Stale-on-update is accepted — standard social-media pattern.
// `@Default('Anónimo')` handles legacy Firestore docs that predate this field —
// json_serializable applies the default when the JSON key is missing.
  @override
  String get authorDisplayName;
  @override
  String? get authorAvatarUrl;
  @override
  String? get authorGymId;
  @override
  String get text;
  @override
  RoutineTag? get routineTag;
  @override
  PostPrivacy get privacy;
  @override
  @TimestampConverter()
  DateTime get createdAt;

  /// Create a copy of Post
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PostImplCopyWith<_$PostImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
