// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'public_profile_view.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$PublicProfileView {
  String get authorDisplayName => throw _privateConstructorUsedError;
  String? get authorAvatarUrl => throw _privateConstructorUsedError;
  String? get authorGymId => throw _privateConstructorUsedError;
  Friendship? get friendship => throw _privateConstructorUsedError;
  bool get isSelf => throw _privateConstructorUsedError;
  int? get workoutsCount => throw _privateConstructorUsedError;
  int? get racha => throw _privateConstructorUsedError;
  int? get followersCount => throw _privateConstructorUsedError;
  int? get followingCount => throw _privateConstructorUsedError;

  /// Create a copy of PublicProfileView
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PublicProfileViewCopyWith<PublicProfileView> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PublicProfileViewCopyWith<$Res> {
  factory $PublicProfileViewCopyWith(
          PublicProfileView value, $Res Function(PublicProfileView) then) =
      _$PublicProfileViewCopyWithImpl<$Res, PublicProfileView>;
  @useResult
  $Res call(
      {String authorDisplayName,
      String? authorAvatarUrl,
      String? authorGymId,
      Friendship? friendship,
      bool isSelf,
      int? workoutsCount,
      int? racha,
      int? followersCount,
      int? followingCount});

  $FriendshipCopyWith<$Res>? get friendship;
}

/// @nodoc
class _$PublicProfileViewCopyWithImpl<$Res, $Val extends PublicProfileView>
    implements $PublicProfileViewCopyWith<$Res> {
  _$PublicProfileViewCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PublicProfileView
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? authorDisplayName = null,
    Object? authorAvatarUrl = freezed,
    Object? authorGymId = freezed,
    Object? friendship = freezed,
    Object? isSelf = null,
    Object? workoutsCount = freezed,
    Object? racha = freezed,
    Object? followersCount = freezed,
    Object? followingCount = freezed,
  }) {
    return _then(_value.copyWith(
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
      friendship: freezed == friendship
          ? _value.friendship
          : friendship // ignore: cast_nullable_to_non_nullable
              as Friendship?,
      isSelf: null == isSelf
          ? _value.isSelf
          : isSelf // ignore: cast_nullable_to_non_nullable
              as bool,
      workoutsCount: freezed == workoutsCount
          ? _value.workoutsCount
          : workoutsCount // ignore: cast_nullable_to_non_nullable
              as int?,
      racha: freezed == racha
          ? _value.racha
          : racha // ignore: cast_nullable_to_non_nullable
              as int?,
      followersCount: freezed == followersCount
          ? _value.followersCount
          : followersCount // ignore: cast_nullable_to_non_nullable
              as int?,
      followingCount: freezed == followingCount
          ? _value.followingCount
          : followingCount // ignore: cast_nullable_to_non_nullable
              as int?,
    ) as $Val);
  }

  /// Create a copy of PublicProfileView
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $FriendshipCopyWith<$Res>? get friendship {
    if (_value.friendship == null) {
      return null;
    }

    return $FriendshipCopyWith<$Res>(_value.friendship!, (value) {
      return _then(_value.copyWith(friendship: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$PublicProfileViewImplCopyWith<$Res>
    implements $PublicProfileViewCopyWith<$Res> {
  factory _$$PublicProfileViewImplCopyWith(_$PublicProfileViewImpl value,
          $Res Function(_$PublicProfileViewImpl) then) =
      __$$PublicProfileViewImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String authorDisplayName,
      String? authorAvatarUrl,
      String? authorGymId,
      Friendship? friendship,
      bool isSelf,
      int? workoutsCount,
      int? racha,
      int? followersCount,
      int? followingCount});

  @override
  $FriendshipCopyWith<$Res>? get friendship;
}

/// @nodoc
class __$$PublicProfileViewImplCopyWithImpl<$Res>
    extends _$PublicProfileViewCopyWithImpl<$Res, _$PublicProfileViewImpl>
    implements _$$PublicProfileViewImplCopyWith<$Res> {
  __$$PublicProfileViewImplCopyWithImpl(_$PublicProfileViewImpl _value,
      $Res Function(_$PublicProfileViewImpl) _then)
      : super(_value, _then);

  /// Create a copy of PublicProfileView
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? authorDisplayName = null,
    Object? authorAvatarUrl = freezed,
    Object? authorGymId = freezed,
    Object? friendship = freezed,
    Object? isSelf = null,
    Object? workoutsCount = freezed,
    Object? racha = freezed,
    Object? followersCount = freezed,
    Object? followingCount = freezed,
  }) {
    return _then(_$PublicProfileViewImpl(
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
      friendship: freezed == friendship
          ? _value.friendship
          : friendship // ignore: cast_nullable_to_non_nullable
              as Friendship?,
      isSelf: null == isSelf
          ? _value.isSelf
          : isSelf // ignore: cast_nullable_to_non_nullable
              as bool,
      workoutsCount: freezed == workoutsCount
          ? _value.workoutsCount
          : workoutsCount // ignore: cast_nullable_to_non_nullable
              as int?,
      racha: freezed == racha
          ? _value.racha
          : racha // ignore: cast_nullable_to_non_nullable
              as int?,
      followersCount: freezed == followersCount
          ? _value.followersCount
          : followersCount // ignore: cast_nullable_to_non_nullable
              as int?,
      followingCount: freezed == followingCount
          ? _value.followingCount
          : followingCount // ignore: cast_nullable_to_non_nullable
              as int?,
    ));
  }
}

/// @nodoc

class _$PublicProfileViewImpl implements _PublicProfileView {
  const _$PublicProfileViewImpl(
      {required this.authorDisplayName,
      required this.authorAvatarUrl,
      required this.authorGymId,
      required this.friendship,
      required this.isSelf,
      this.workoutsCount,
      this.racha,
      this.followersCount,
      this.followingCount});

  @override
  final String authorDisplayName;
  @override
  final String? authorAvatarUrl;
  @override
  final String? authorGymId;
  @override
  final Friendship? friendship;
  @override
  final bool isSelf;
  @override
  final int? workoutsCount;
  @override
  final int? racha;
  @override
  final int? followersCount;
  @override
  final int? followingCount;

  @override
  String toString() {
    return 'PublicProfileView(authorDisplayName: $authorDisplayName, authorAvatarUrl: $authorAvatarUrl, authorGymId: $authorGymId, friendship: $friendship, isSelf: $isSelf, workoutsCount: $workoutsCount, racha: $racha, followersCount: $followersCount, followingCount: $followingCount)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PublicProfileViewImpl &&
            (identical(other.authorDisplayName, authorDisplayName) ||
                other.authorDisplayName == authorDisplayName) &&
            (identical(other.authorAvatarUrl, authorAvatarUrl) ||
                other.authorAvatarUrl == authorAvatarUrl) &&
            (identical(other.authorGymId, authorGymId) ||
                other.authorGymId == authorGymId) &&
            (identical(other.friendship, friendship) ||
                other.friendship == friendship) &&
            (identical(other.isSelf, isSelf) || other.isSelf == isSelf) &&
            (identical(other.workoutsCount, workoutsCount) ||
                other.workoutsCount == workoutsCount) &&
            (identical(other.racha, racha) || other.racha == racha) &&
            (identical(other.followersCount, followersCount) ||
                other.followersCount == followersCount) &&
            (identical(other.followingCount, followingCount) ||
                other.followingCount == followingCount));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      authorDisplayName,
      authorAvatarUrl,
      authorGymId,
      friendship,
      isSelf,
      workoutsCount,
      racha,
      followersCount,
      followingCount);

  /// Create a copy of PublicProfileView
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PublicProfileViewImplCopyWith<_$PublicProfileViewImpl> get copyWith =>
      __$$PublicProfileViewImplCopyWithImpl<_$PublicProfileViewImpl>(
          this, _$identity);
}

abstract class _PublicProfileView implements PublicProfileView {
  const factory _PublicProfileView(
      {required final String authorDisplayName,
      required final String? authorAvatarUrl,
      required final String? authorGymId,
      required final Friendship? friendship,
      required final bool isSelf,
      final int? workoutsCount,
      final int? racha,
      final int? followersCount,
      final int? followingCount}) = _$PublicProfileViewImpl;

  @override
  String get authorDisplayName;
  @override
  String? get authorAvatarUrl;
  @override
  String? get authorGymId;
  @override
  Friendship? get friendship;
  @override
  bool get isSelf;
  @override
  int? get workoutsCount;
  @override
  int? get racha;
  @override
  int? get followersCount;
  @override
  int? get followingCount;

  /// Create a copy of PublicProfileView
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PublicProfileViewImplCopyWith<_$PublicProfileViewImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
