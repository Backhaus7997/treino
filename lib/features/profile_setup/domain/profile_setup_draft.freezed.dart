// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'profile_setup_draft.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$ProfileSetupDraft {
  /// Step 1
  String? get username => throw _privateConstructorUsedError;

  /// Step 1 — path local del avatar elegido del image_picker. Se uploadea
  /// a Firebase Storage en el submit final, y la URL resultante se persiste
  /// como `avatarRemoteUrl`.
  String? get avatarLocalPath => throw _privateConstructorUsedError;

  /// Step 1 — URL HTTPS del avatar después del upload a Storage. `null`
  /// mientras el usuario no haya elegido foto o el upload no haya completado.
  String? get avatarRemoteUrl => throw _privateConstructorUsedError;

  /// Step 2 — `null` si el usuario aún no eligió, o [kNoGymId] si optó por
  /// "OTRO GYM / SIN GYM".
  String? get gymId => throw _privateConstructorUsedError;

  /// Step 3
  ExperienceLevel? get experience => throw _privateConstructorUsedError;

  /// Step 3
  Gender? get gender => throw _privateConstructorUsedError;

  /// Step 4 — peso corporal en kilogramos.
  double? get weightKg => throw _privateConstructorUsedError;

  /// Step 4 — altura en centímetros.
  double? get heightCm => throw _privateConstructorUsedError;

  /// Create a copy of ProfileSetupDraft
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ProfileSetupDraftCopyWith<ProfileSetupDraft> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ProfileSetupDraftCopyWith<$Res> {
  factory $ProfileSetupDraftCopyWith(
          ProfileSetupDraft value, $Res Function(ProfileSetupDraft) then) =
      _$ProfileSetupDraftCopyWithImpl<$Res, ProfileSetupDraft>;
  @useResult
  $Res call(
      {String? username,
      String? avatarLocalPath,
      String? avatarRemoteUrl,
      String? gymId,
      ExperienceLevel? experience,
      Gender? gender,
      double? weightKg,
      double? heightCm});
}

/// @nodoc
class _$ProfileSetupDraftCopyWithImpl<$Res, $Val extends ProfileSetupDraft>
    implements $ProfileSetupDraftCopyWith<$Res> {
  _$ProfileSetupDraftCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ProfileSetupDraft
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? username = freezed,
    Object? avatarLocalPath = freezed,
    Object? avatarRemoteUrl = freezed,
    Object? gymId = freezed,
    Object? experience = freezed,
    Object? gender = freezed,
    Object? weightKg = freezed,
    Object? heightCm = freezed,
  }) {
    return _then(_value.copyWith(
      username: freezed == username
          ? _value.username
          : username // ignore: cast_nullable_to_non_nullable
              as String?,
      avatarLocalPath: freezed == avatarLocalPath
          ? _value.avatarLocalPath
          : avatarLocalPath // ignore: cast_nullable_to_non_nullable
              as String?,
      avatarRemoteUrl: freezed == avatarRemoteUrl
          ? _value.avatarRemoteUrl
          : avatarRemoteUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      gymId: freezed == gymId
          ? _value.gymId
          : gymId // ignore: cast_nullable_to_non_nullable
              as String?,
      experience: freezed == experience
          ? _value.experience
          : experience // ignore: cast_nullable_to_non_nullable
              as ExperienceLevel?,
      gender: freezed == gender
          ? _value.gender
          : gender // ignore: cast_nullable_to_non_nullable
              as Gender?,
      weightKg: freezed == weightKg
          ? _value.weightKg
          : weightKg // ignore: cast_nullable_to_non_nullable
              as double?,
      heightCm: freezed == heightCm
          ? _value.heightCm
          : heightCm // ignore: cast_nullable_to_non_nullable
              as double?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ProfileSetupDraftImplCopyWith<$Res>
    implements $ProfileSetupDraftCopyWith<$Res> {
  factory _$$ProfileSetupDraftImplCopyWith(_$ProfileSetupDraftImpl value,
          $Res Function(_$ProfileSetupDraftImpl) then) =
      __$$ProfileSetupDraftImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String? username,
      String? avatarLocalPath,
      String? avatarRemoteUrl,
      String? gymId,
      ExperienceLevel? experience,
      Gender? gender,
      double? weightKg,
      double? heightCm});
}

/// @nodoc
class __$$ProfileSetupDraftImplCopyWithImpl<$Res>
    extends _$ProfileSetupDraftCopyWithImpl<$Res, _$ProfileSetupDraftImpl>
    implements _$$ProfileSetupDraftImplCopyWith<$Res> {
  __$$ProfileSetupDraftImplCopyWithImpl(_$ProfileSetupDraftImpl _value,
      $Res Function(_$ProfileSetupDraftImpl) _then)
      : super(_value, _then);

  /// Create a copy of ProfileSetupDraft
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? username = freezed,
    Object? avatarLocalPath = freezed,
    Object? avatarRemoteUrl = freezed,
    Object? gymId = freezed,
    Object? experience = freezed,
    Object? gender = freezed,
    Object? weightKg = freezed,
    Object? heightCm = freezed,
  }) {
    return _then(_$ProfileSetupDraftImpl(
      username: freezed == username
          ? _value.username
          : username // ignore: cast_nullable_to_non_nullable
              as String?,
      avatarLocalPath: freezed == avatarLocalPath
          ? _value.avatarLocalPath
          : avatarLocalPath // ignore: cast_nullable_to_non_nullable
              as String?,
      avatarRemoteUrl: freezed == avatarRemoteUrl
          ? _value.avatarRemoteUrl
          : avatarRemoteUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      gymId: freezed == gymId
          ? _value.gymId
          : gymId // ignore: cast_nullable_to_non_nullable
              as String?,
      experience: freezed == experience
          ? _value.experience
          : experience // ignore: cast_nullable_to_non_nullable
              as ExperienceLevel?,
      gender: freezed == gender
          ? _value.gender
          : gender // ignore: cast_nullable_to_non_nullable
              as Gender?,
      weightKg: freezed == weightKg
          ? _value.weightKg
          : weightKg // ignore: cast_nullable_to_non_nullable
              as double?,
      heightCm: freezed == heightCm
          ? _value.heightCm
          : heightCm // ignore: cast_nullable_to_non_nullable
              as double?,
    ));
  }
}

/// @nodoc

class _$ProfileSetupDraftImpl extends _ProfileSetupDraft {
  const _$ProfileSetupDraftImpl(
      {this.username,
      this.avatarLocalPath,
      this.avatarRemoteUrl,
      this.gymId,
      this.experience,
      this.gender,
      this.weightKg,
      this.heightCm})
      : super._();

  /// Step 1
  @override
  final String? username;

  /// Step 1 — path local del avatar elegido del image_picker. Se uploadea
  /// a Firebase Storage en el submit final, y la URL resultante se persiste
  /// como `avatarRemoteUrl`.
  @override
  final String? avatarLocalPath;

  /// Step 1 — URL HTTPS del avatar después del upload a Storage. `null`
  /// mientras el usuario no haya elegido foto o el upload no haya completado.
  @override
  final String? avatarRemoteUrl;

  /// Step 2 — `null` si el usuario aún no eligió, o [kNoGymId] si optó por
  /// "OTRO GYM / SIN GYM".
  @override
  final String? gymId;

  /// Step 3
  @override
  final ExperienceLevel? experience;

  /// Step 3
  @override
  final Gender? gender;

  /// Step 4 — peso corporal en kilogramos.
  @override
  final double? weightKg;

  /// Step 4 — altura en centímetros.
  @override
  final double? heightCm;

  @override
  String toString() {
    return 'ProfileSetupDraft(username: $username, avatarLocalPath: $avatarLocalPath, avatarRemoteUrl: $avatarRemoteUrl, gymId: $gymId, experience: $experience, gender: $gender, weightKg: $weightKg, heightCm: $heightCm)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ProfileSetupDraftImpl &&
            (identical(other.username, username) ||
                other.username == username) &&
            (identical(other.avatarLocalPath, avatarLocalPath) ||
                other.avatarLocalPath == avatarLocalPath) &&
            (identical(other.avatarRemoteUrl, avatarRemoteUrl) ||
                other.avatarRemoteUrl == avatarRemoteUrl) &&
            (identical(other.gymId, gymId) || other.gymId == gymId) &&
            (identical(other.experience, experience) ||
                other.experience == experience) &&
            (identical(other.gender, gender) || other.gender == gender) &&
            (identical(other.weightKg, weightKg) ||
                other.weightKg == weightKg) &&
            (identical(other.heightCm, heightCm) ||
                other.heightCm == heightCm));
  }

  @override
  int get hashCode => Object.hash(runtimeType, username, avatarLocalPath,
      avatarRemoteUrl, gymId, experience, gender, weightKg, heightCm);

  /// Create a copy of ProfileSetupDraft
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ProfileSetupDraftImplCopyWith<_$ProfileSetupDraftImpl> get copyWith =>
      __$$ProfileSetupDraftImplCopyWithImpl<_$ProfileSetupDraftImpl>(
          this, _$identity);
}

abstract class _ProfileSetupDraft extends ProfileSetupDraft {
  const factory _ProfileSetupDraft(
      {final String? username,
      final String? avatarLocalPath,
      final String? avatarRemoteUrl,
      final String? gymId,
      final ExperienceLevel? experience,
      final Gender? gender,
      final double? weightKg,
      final double? heightCm}) = _$ProfileSetupDraftImpl;
  const _ProfileSetupDraft._() : super._();

  /// Step 1
  @override
  String? get username;

  /// Step 1 — path local del avatar elegido del image_picker. Se uploadea
  /// a Firebase Storage en el submit final, y la URL resultante se persiste
  /// como `avatarRemoteUrl`.
  @override
  String? get avatarLocalPath;

  /// Step 1 — URL HTTPS del avatar después del upload a Storage. `null`
  /// mientras el usuario no haya elegido foto o el upload no haya completado.
  @override
  String? get avatarRemoteUrl;

  /// Step 2 — `null` si el usuario aún no eligió, o [kNoGymId] si optó por
  /// "OTRO GYM / SIN GYM".
  @override
  String? get gymId;

  /// Step 3
  @override
  ExperienceLevel? get experience;

  /// Step 3
  @override
  Gender? get gender;

  /// Step 4 — peso corporal en kilogramos.
  @override
  double? get weightKg;

  /// Step 4 — altura en centímetros.
  @override
  double? get heightCm;

  /// Create a copy of ProfileSetupDraft
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ProfileSetupDraftImplCopyWith<_$ProfileSetupDraftImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
