// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'user_public_profile.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

UserPublicProfile _$UserPublicProfileFromJson(Map<String, dynamic> json) {
  return _UserPublicProfile.fromJson(json);
}

/// @nodoc
mixin _$UserPublicProfile {
  String get uid => throw _privateConstructorUsedError;
  String? get displayName => throw _privateConstructorUsedError;
  String? get displayNameLowercase => throw _privateConstructorUsedError;
  String? get avatarUrl => throw _privateConstructorUsedError;
  String? get gymId => throw _privateConstructorUsedError;

  /// Denormalized composed brand-branch display label (e.g.
  /// "SportClub - Belgrano", or just the brand name for independent
  /// single-branch gyms). Dual-written by `UserRepository.update()`
  /// alongside `gymId` at profile-save time — mirrors `CheckIn.gymName`.
  /// Nullable for backward-compat with profiles saved before this field
  /// existed (also `null` when `gymId` is `null`/`kNoGymId`/unresolvable).
  /// See gyms-foundation Phase 3 (name resolution + denormalization).
  String? get gymName => throw _privateConstructorUsedError;
  int? get workoutsCount => throw _privateConstructorUsedError;
  int? get racha =>
      throw _privateConstructorUsedError; // ignore: invalid_annotation_target
  @JsonKey(fromJson: _nonNegativeCount)
  int? get followersCount =>
      throw _privateConstructorUsedError; // ignore: invalid_annotation_target
  @JsonKey(fromJson: _nonNegativeCount)
  int? get followingCount =>
      throw _privateConstructorUsedError; // Opt-in flag a trainer can flip to expose ALL their `trainer-template`
// routines to their active athletes (a "buffet" the athletes can browse
// and run sessions from without being explicitly assigned). Defaults to
// false so existing docs without the field decode safely and no template
// becomes public retroactively. Off = athletes only see plans the
// trainer assigned to them one-by-one.
  bool get sharedTemplatesWithAthletes => throw _privateConstructorUsedError;

  /// Serializes this UserPublicProfile to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of UserPublicProfile
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $UserPublicProfileCopyWith<UserPublicProfile> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $UserPublicProfileCopyWith<$Res> {
  factory $UserPublicProfileCopyWith(
          UserPublicProfile value, $Res Function(UserPublicProfile) then) =
      _$UserPublicProfileCopyWithImpl<$Res, UserPublicProfile>;
  @useResult
  $Res call(
      {String uid,
      String? displayName,
      String? displayNameLowercase,
      String? avatarUrl,
      String? gymId,
      String? gymName,
      int? workoutsCount,
      int? racha,
      @JsonKey(fromJson: _nonNegativeCount) int? followersCount,
      @JsonKey(fromJson: _nonNegativeCount) int? followingCount,
      bool sharedTemplatesWithAthletes});
}

/// @nodoc
class _$UserPublicProfileCopyWithImpl<$Res, $Val extends UserPublicProfile>
    implements $UserPublicProfileCopyWith<$Res> {
  _$UserPublicProfileCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of UserPublicProfile
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? uid = null,
    Object? displayName = freezed,
    Object? displayNameLowercase = freezed,
    Object? avatarUrl = freezed,
    Object? gymId = freezed,
    Object? gymName = freezed,
    Object? workoutsCount = freezed,
    Object? racha = freezed,
    Object? followersCount = freezed,
    Object? followingCount = freezed,
    Object? sharedTemplatesWithAthletes = null,
  }) {
    return _then(_value.copyWith(
      uid: null == uid
          ? _value.uid
          : uid // ignore: cast_nullable_to_non_nullable
              as String,
      displayName: freezed == displayName
          ? _value.displayName
          : displayName // ignore: cast_nullable_to_non_nullable
              as String?,
      displayNameLowercase: freezed == displayNameLowercase
          ? _value.displayNameLowercase
          : displayNameLowercase // ignore: cast_nullable_to_non_nullable
              as String?,
      avatarUrl: freezed == avatarUrl
          ? _value.avatarUrl
          : avatarUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      gymId: freezed == gymId
          ? _value.gymId
          : gymId // ignore: cast_nullable_to_non_nullable
              as String?,
      gymName: freezed == gymName
          ? _value.gymName
          : gymName // ignore: cast_nullable_to_non_nullable
              as String?,
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
      sharedTemplatesWithAthletes: null == sharedTemplatesWithAthletes
          ? _value.sharedTemplatesWithAthletes
          : sharedTemplatesWithAthletes // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$UserPublicProfileImplCopyWith<$Res>
    implements $UserPublicProfileCopyWith<$Res> {
  factory _$$UserPublicProfileImplCopyWith(_$UserPublicProfileImpl value,
          $Res Function(_$UserPublicProfileImpl) then) =
      __$$UserPublicProfileImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String uid,
      String? displayName,
      String? displayNameLowercase,
      String? avatarUrl,
      String? gymId,
      String? gymName,
      int? workoutsCount,
      int? racha,
      @JsonKey(fromJson: _nonNegativeCount) int? followersCount,
      @JsonKey(fromJson: _nonNegativeCount) int? followingCount,
      bool sharedTemplatesWithAthletes});
}

/// @nodoc
class __$$UserPublicProfileImplCopyWithImpl<$Res>
    extends _$UserPublicProfileCopyWithImpl<$Res, _$UserPublicProfileImpl>
    implements _$$UserPublicProfileImplCopyWith<$Res> {
  __$$UserPublicProfileImplCopyWithImpl(_$UserPublicProfileImpl _value,
      $Res Function(_$UserPublicProfileImpl) _then)
      : super(_value, _then);

  /// Create a copy of UserPublicProfile
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? uid = null,
    Object? displayName = freezed,
    Object? displayNameLowercase = freezed,
    Object? avatarUrl = freezed,
    Object? gymId = freezed,
    Object? gymName = freezed,
    Object? workoutsCount = freezed,
    Object? racha = freezed,
    Object? followersCount = freezed,
    Object? followingCount = freezed,
    Object? sharedTemplatesWithAthletes = null,
  }) {
    return _then(_$UserPublicProfileImpl(
      uid: null == uid
          ? _value.uid
          : uid // ignore: cast_nullable_to_non_nullable
              as String,
      displayName: freezed == displayName
          ? _value.displayName
          : displayName // ignore: cast_nullable_to_non_nullable
              as String?,
      displayNameLowercase: freezed == displayNameLowercase
          ? _value.displayNameLowercase
          : displayNameLowercase // ignore: cast_nullable_to_non_nullable
              as String?,
      avatarUrl: freezed == avatarUrl
          ? _value.avatarUrl
          : avatarUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      gymId: freezed == gymId
          ? _value.gymId
          : gymId // ignore: cast_nullable_to_non_nullable
              as String?,
      gymName: freezed == gymName
          ? _value.gymName
          : gymName // ignore: cast_nullable_to_non_nullable
              as String?,
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
      sharedTemplatesWithAthletes: null == sharedTemplatesWithAthletes
          ? _value.sharedTemplatesWithAthletes
          : sharedTemplatesWithAthletes // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$UserPublicProfileImpl implements _UserPublicProfile {
  const _$UserPublicProfileImpl(
      {required this.uid,
      this.displayName,
      this.displayNameLowercase,
      this.avatarUrl,
      this.gymId,
      this.gymName,
      this.workoutsCount,
      this.racha,
      @JsonKey(fromJson: _nonNegativeCount) this.followersCount,
      @JsonKey(fromJson: _nonNegativeCount) this.followingCount,
      this.sharedTemplatesWithAthletes = false});

  factory _$UserPublicProfileImpl.fromJson(Map<String, dynamic> json) =>
      _$$UserPublicProfileImplFromJson(json);

  @override
  final String uid;
  @override
  final String? displayName;
  @override
  final String? displayNameLowercase;
  @override
  final String? avatarUrl;
  @override
  final String? gymId;

  /// Denormalized composed brand-branch display label (e.g.
  /// "SportClub - Belgrano", or just the brand name for independent
  /// single-branch gyms). Dual-written by `UserRepository.update()`
  /// alongside `gymId` at profile-save time — mirrors `CheckIn.gymName`.
  /// Nullable for backward-compat with profiles saved before this field
  /// existed (also `null` when `gymId` is `null`/`kNoGymId`/unresolvable).
  /// See gyms-foundation Phase 3 (name resolution + denormalization).
  @override
  final String? gymName;
  @override
  final int? workoutsCount;
  @override
  final int? racha;
// ignore: invalid_annotation_target
  @override
  @JsonKey(fromJson: _nonNegativeCount)
  final int? followersCount;
// ignore: invalid_annotation_target
  @override
  @JsonKey(fromJson: _nonNegativeCount)
  final int? followingCount;
// Opt-in flag a trainer can flip to expose ALL their `trainer-template`
// routines to their active athletes (a "buffet" the athletes can browse
// and run sessions from without being explicitly assigned). Defaults to
// false so existing docs without the field decode safely and no template
// becomes public retroactively. Off = athletes only see plans the
// trainer assigned to them one-by-one.
  @override
  @JsonKey()
  final bool sharedTemplatesWithAthletes;

  @override
  String toString() {
    return 'UserPublicProfile(uid: $uid, displayName: $displayName, displayNameLowercase: $displayNameLowercase, avatarUrl: $avatarUrl, gymId: $gymId, gymName: $gymName, workoutsCount: $workoutsCount, racha: $racha, followersCount: $followersCount, followingCount: $followingCount, sharedTemplatesWithAthletes: $sharedTemplatesWithAthletes)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UserPublicProfileImpl &&
            (identical(other.uid, uid) || other.uid == uid) &&
            (identical(other.displayName, displayName) ||
                other.displayName == displayName) &&
            (identical(other.displayNameLowercase, displayNameLowercase) ||
                other.displayNameLowercase == displayNameLowercase) &&
            (identical(other.avatarUrl, avatarUrl) ||
                other.avatarUrl == avatarUrl) &&
            (identical(other.gymId, gymId) || other.gymId == gymId) &&
            (identical(other.gymName, gymName) || other.gymName == gymName) &&
            (identical(other.workoutsCount, workoutsCount) ||
                other.workoutsCount == workoutsCount) &&
            (identical(other.racha, racha) || other.racha == racha) &&
            (identical(other.followersCount, followersCount) ||
                other.followersCount == followersCount) &&
            (identical(other.followingCount, followingCount) ||
                other.followingCount == followingCount) &&
            (identical(other.sharedTemplatesWithAthletes,
                    sharedTemplatesWithAthletes) ||
                other.sharedTemplatesWithAthletes ==
                    sharedTemplatesWithAthletes));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      uid,
      displayName,
      displayNameLowercase,
      avatarUrl,
      gymId,
      gymName,
      workoutsCount,
      racha,
      followersCount,
      followingCount,
      sharedTemplatesWithAthletes);

  /// Create a copy of UserPublicProfile
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$UserPublicProfileImplCopyWith<_$UserPublicProfileImpl> get copyWith =>
      __$$UserPublicProfileImplCopyWithImpl<_$UserPublicProfileImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$UserPublicProfileImplToJson(
      this,
    );
  }
}

abstract class _UserPublicProfile implements UserPublicProfile {
  const factory _UserPublicProfile(
      {required final String uid,
      final String? displayName,
      final String? displayNameLowercase,
      final String? avatarUrl,
      final String? gymId,
      final String? gymName,
      final int? workoutsCount,
      final int? racha,
      @JsonKey(fromJson: _nonNegativeCount) final int? followersCount,
      @JsonKey(fromJson: _nonNegativeCount) final int? followingCount,
      final bool sharedTemplatesWithAthletes}) = _$UserPublicProfileImpl;

  factory _UserPublicProfile.fromJson(Map<String, dynamic> json) =
      _$UserPublicProfileImpl.fromJson;

  @override
  String get uid;
  @override
  String? get displayName;
  @override
  String? get displayNameLowercase;
  @override
  String? get avatarUrl;
  @override
  String? get gymId;

  /// Denormalized composed brand-branch display label (e.g.
  /// "SportClub - Belgrano", or just the brand name for independent
  /// single-branch gyms). Dual-written by `UserRepository.update()`
  /// alongside `gymId` at profile-save time — mirrors `CheckIn.gymName`.
  /// Nullable for backward-compat with profiles saved before this field
  /// existed (also `null` when `gymId` is `null`/`kNoGymId`/unresolvable).
  /// See gyms-foundation Phase 3 (name resolution + denormalization).
  @override
  String? get gymName;
  @override
  int? get workoutsCount;
  @override
  int? get racha; // ignore: invalid_annotation_target
  @override
  @JsonKey(fromJson: _nonNegativeCount)
  int? get followersCount; // ignore: invalid_annotation_target
  @override
  @JsonKey(fromJson: _nonNegativeCount)
  int?
      get followingCount; // Opt-in flag a trainer can flip to expose ALL their `trainer-template`
// routines to their active athletes (a "buffet" the athletes can browse
// and run sessions from without being explicitly assigned). Defaults to
// false so existing docs without the field decode safely and no template
// becomes public retroactively. Off = athletes only see plans the
// trainer assigned to them one-by-one.
  @override
  bool get sharedTemplatesWithAthletes;

  /// Create a copy of UserPublicProfile
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$UserPublicProfileImplCopyWith<_$UserPublicProfileImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
