// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'user_profile.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

UserProfile _$UserProfileFromJson(Map<String, dynamic> json) {
  return _UserProfile.fromJson(json);
}

/// @nodoc
mixin _$UserProfile {
  String get uid => throw _privateConstructorUsedError;
  String get email => throw _privateConstructorUsedError;
  String? get displayName => throw _privateConstructorUsedError;
  UserRole get role => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get createdAt => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get updatedAt => throw _privateConstructorUsedError;
  String? get gymId => throw _privateConstructorUsedError;
  double? get bodyWeightKg => throw _privateConstructorUsedError;
  int? get heightCm => throw _privateConstructorUsedError;
  Gender? get gender => throw _privateConstructorUsedError;
  ExperienceLevel? get experienceLevel => throw _privateConstructorUsedError;
  String? get avatarUrl => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime? get bornAt =>
      throw _privateConstructorUsedError; // ── Trainer-specific (Fase 5 Etapa 1 foundations) ───────────────────
  String? get trainerBio => throw _privateConstructorUsedError;
  String? get trainerSpecialty => throw _privateConstructorUsedError;
  int? get trainerMonthlyRate =>
      throw _privateConstructorUsedError; // ── Multi-location (Fase 6 Etapa 0) ────────────────────────────────
//
// `trainerLatitude/Longitude/Geohash` (singulares, marcados DEPRECATED)
// se mantienen por backward compat — clientes viejos siguen leyendo el
// campo legacy hasta que actualicen. La migration de `treino-dev`
// (scripts/migrate_trainer_locations.js) convierte cada doc legacy a
// `trainerLocations: [{type: custom OR gym, ...}]`. Cleanup PR borra
// los campos legacy cuando todas las clientes estén en la versión nueva.
//
// `trainerLocations` mezcla gyms del catálogo (`type == gym`, `gymId`
// referencia `gyms/{gymId}`) y lugares propios (`type == custom`,
// `customLabel` lleva el nombre).
//
// `trainerGeohashes` es array derivado en write-time desde
// `trainerLocations` — necesario para el query
// `where('trainerGeohashes', array-contains-any, [vecinos del atleta])`
// que reemplaza el `where('trainerGeohash', >=, prefix5)` original.
//
// `trainerOffersOnline` es flag independiente. La combinación
// `trainerLocations.isEmpty && !trainerOffersOnline` es inválida —
// UserRepository.update() la rechaza con ArgumentError antes del write.
  double? get trainerLatitude =>
      throw _privateConstructorUsedError; // DEPRECATED
  double? get trainerLongitude =>
      throw _privateConstructorUsedError; // DEPRECATED
  String? get trainerGeohash =>
      throw _privateConstructorUsedError; // DEPRECATED
  List<TrainerLocation> get trainerLocations =>
      throw _privateConstructorUsedError;
  List<String> get trainerGeohashes => throw _privateConstructorUsedError;
  bool get trainerOffersOnline => throw _privateConstructorUsedError;

  /// Serializes this UserProfile to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of UserProfile
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $UserProfileCopyWith<UserProfile> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $UserProfileCopyWith<$Res> {
  factory $UserProfileCopyWith(
          UserProfile value, $Res Function(UserProfile) then) =
      _$UserProfileCopyWithImpl<$Res, UserProfile>;
  @useResult
  $Res call(
      {String uid,
      String email,
      String? displayName,
      UserRole role,
      @TimestampConverter() DateTime createdAt,
      @TimestampConverter() DateTime updatedAt,
      String? gymId,
      double? bodyWeightKg,
      int? heightCm,
      Gender? gender,
      ExperienceLevel? experienceLevel,
      String? avatarUrl,
      @TimestampConverter() DateTime? bornAt,
      String? trainerBio,
      String? trainerSpecialty,
      int? trainerMonthlyRate,
      double? trainerLatitude,
      double? trainerLongitude,
      String? trainerGeohash,
      List<TrainerLocation> trainerLocations,
      List<String> trainerGeohashes,
      bool trainerOffersOnline});
}

/// @nodoc
class _$UserProfileCopyWithImpl<$Res, $Val extends UserProfile>
    implements $UserProfileCopyWith<$Res> {
  _$UserProfileCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of UserProfile
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? uid = null,
    Object? email = null,
    Object? displayName = freezed,
    Object? role = null,
    Object? createdAt = null,
    Object? updatedAt = null,
    Object? gymId = freezed,
    Object? bodyWeightKg = freezed,
    Object? heightCm = freezed,
    Object? gender = freezed,
    Object? experienceLevel = freezed,
    Object? avatarUrl = freezed,
    Object? bornAt = freezed,
    Object? trainerBio = freezed,
    Object? trainerSpecialty = freezed,
    Object? trainerMonthlyRate = freezed,
    Object? trainerLatitude = freezed,
    Object? trainerLongitude = freezed,
    Object? trainerGeohash = freezed,
    Object? trainerLocations = null,
    Object? trainerGeohashes = null,
    Object? trainerOffersOnline = null,
  }) {
    return _then(_value.copyWith(
      uid: null == uid
          ? _value.uid
          : uid // ignore: cast_nullable_to_non_nullable
              as String,
      email: null == email
          ? _value.email
          : email // ignore: cast_nullable_to_non_nullable
              as String,
      displayName: freezed == displayName
          ? _value.displayName
          : displayName // ignore: cast_nullable_to_non_nullable
              as String?,
      role: null == role
          ? _value.role
          : role // ignore: cast_nullable_to_non_nullable
              as UserRole,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      updatedAt: null == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      gymId: freezed == gymId
          ? _value.gymId
          : gymId // ignore: cast_nullable_to_non_nullable
              as String?,
      bodyWeightKg: freezed == bodyWeightKg
          ? _value.bodyWeightKg
          : bodyWeightKg // ignore: cast_nullable_to_non_nullable
              as double?,
      heightCm: freezed == heightCm
          ? _value.heightCm
          : heightCm // ignore: cast_nullable_to_non_nullable
              as int?,
      gender: freezed == gender
          ? _value.gender
          : gender // ignore: cast_nullable_to_non_nullable
              as Gender?,
      experienceLevel: freezed == experienceLevel
          ? _value.experienceLevel
          : experienceLevel // ignore: cast_nullable_to_non_nullable
              as ExperienceLevel?,
      avatarUrl: freezed == avatarUrl
          ? _value.avatarUrl
          : avatarUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      bornAt: freezed == bornAt
          ? _value.bornAt
          : bornAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      trainerBio: freezed == trainerBio
          ? _value.trainerBio
          : trainerBio // ignore: cast_nullable_to_non_nullable
              as String?,
      trainerSpecialty: freezed == trainerSpecialty
          ? _value.trainerSpecialty
          : trainerSpecialty // ignore: cast_nullable_to_non_nullable
              as String?,
      trainerMonthlyRate: freezed == trainerMonthlyRate
          ? _value.trainerMonthlyRate
          : trainerMonthlyRate // ignore: cast_nullable_to_non_nullable
              as int?,
      trainerLatitude: freezed == trainerLatitude
          ? _value.trainerLatitude
          : trainerLatitude // ignore: cast_nullable_to_non_nullable
              as double?,
      trainerLongitude: freezed == trainerLongitude
          ? _value.trainerLongitude
          : trainerLongitude // ignore: cast_nullable_to_non_nullable
              as double?,
      trainerGeohash: freezed == trainerGeohash
          ? _value.trainerGeohash
          : trainerGeohash // ignore: cast_nullable_to_non_nullable
              as String?,
      trainerLocations: null == trainerLocations
          ? _value.trainerLocations
          : trainerLocations // ignore: cast_nullable_to_non_nullable
              as List<TrainerLocation>,
      trainerGeohashes: null == trainerGeohashes
          ? _value.trainerGeohashes
          : trainerGeohashes // ignore: cast_nullable_to_non_nullable
              as List<String>,
      trainerOffersOnline: null == trainerOffersOnline
          ? _value.trainerOffersOnline
          : trainerOffersOnline // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$UserProfileImplCopyWith<$Res>
    implements $UserProfileCopyWith<$Res> {
  factory _$$UserProfileImplCopyWith(
          _$UserProfileImpl value, $Res Function(_$UserProfileImpl) then) =
      __$$UserProfileImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String uid,
      String email,
      String? displayName,
      UserRole role,
      @TimestampConverter() DateTime createdAt,
      @TimestampConverter() DateTime updatedAt,
      String? gymId,
      double? bodyWeightKg,
      int? heightCm,
      Gender? gender,
      ExperienceLevel? experienceLevel,
      String? avatarUrl,
      @TimestampConverter() DateTime? bornAt,
      String? trainerBio,
      String? trainerSpecialty,
      int? trainerMonthlyRate,
      double? trainerLatitude,
      double? trainerLongitude,
      String? trainerGeohash,
      List<TrainerLocation> trainerLocations,
      List<String> trainerGeohashes,
      bool trainerOffersOnline});
}

/// @nodoc
class __$$UserProfileImplCopyWithImpl<$Res>
    extends _$UserProfileCopyWithImpl<$Res, _$UserProfileImpl>
    implements _$$UserProfileImplCopyWith<$Res> {
  __$$UserProfileImplCopyWithImpl(
      _$UserProfileImpl _value, $Res Function(_$UserProfileImpl) _then)
      : super(_value, _then);

  /// Create a copy of UserProfile
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? uid = null,
    Object? email = null,
    Object? displayName = freezed,
    Object? role = null,
    Object? createdAt = null,
    Object? updatedAt = null,
    Object? gymId = freezed,
    Object? bodyWeightKg = freezed,
    Object? heightCm = freezed,
    Object? gender = freezed,
    Object? experienceLevel = freezed,
    Object? avatarUrl = freezed,
    Object? bornAt = freezed,
    Object? trainerBio = freezed,
    Object? trainerSpecialty = freezed,
    Object? trainerMonthlyRate = freezed,
    Object? trainerLatitude = freezed,
    Object? trainerLongitude = freezed,
    Object? trainerGeohash = freezed,
    Object? trainerLocations = null,
    Object? trainerGeohashes = null,
    Object? trainerOffersOnline = null,
  }) {
    return _then(_$UserProfileImpl(
      uid: null == uid
          ? _value.uid
          : uid // ignore: cast_nullable_to_non_nullable
              as String,
      email: null == email
          ? _value.email
          : email // ignore: cast_nullable_to_non_nullable
              as String,
      displayName: freezed == displayName
          ? _value.displayName
          : displayName // ignore: cast_nullable_to_non_nullable
              as String?,
      role: null == role
          ? _value.role
          : role // ignore: cast_nullable_to_non_nullable
              as UserRole,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      updatedAt: null == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      gymId: freezed == gymId
          ? _value.gymId
          : gymId // ignore: cast_nullable_to_non_nullable
              as String?,
      bodyWeightKg: freezed == bodyWeightKg
          ? _value.bodyWeightKg
          : bodyWeightKg // ignore: cast_nullable_to_non_nullable
              as double?,
      heightCm: freezed == heightCm
          ? _value.heightCm
          : heightCm // ignore: cast_nullable_to_non_nullable
              as int?,
      gender: freezed == gender
          ? _value.gender
          : gender // ignore: cast_nullable_to_non_nullable
              as Gender?,
      experienceLevel: freezed == experienceLevel
          ? _value.experienceLevel
          : experienceLevel // ignore: cast_nullable_to_non_nullable
              as ExperienceLevel?,
      avatarUrl: freezed == avatarUrl
          ? _value.avatarUrl
          : avatarUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      bornAt: freezed == bornAt
          ? _value.bornAt
          : bornAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      trainerBio: freezed == trainerBio
          ? _value.trainerBio
          : trainerBio // ignore: cast_nullable_to_non_nullable
              as String?,
      trainerSpecialty: freezed == trainerSpecialty
          ? _value.trainerSpecialty
          : trainerSpecialty // ignore: cast_nullable_to_non_nullable
              as String?,
      trainerMonthlyRate: freezed == trainerMonthlyRate
          ? _value.trainerMonthlyRate
          : trainerMonthlyRate // ignore: cast_nullable_to_non_nullable
              as int?,
      trainerLatitude: freezed == trainerLatitude
          ? _value.trainerLatitude
          : trainerLatitude // ignore: cast_nullable_to_non_nullable
              as double?,
      trainerLongitude: freezed == trainerLongitude
          ? _value.trainerLongitude
          : trainerLongitude // ignore: cast_nullable_to_non_nullable
              as double?,
      trainerGeohash: freezed == trainerGeohash
          ? _value.trainerGeohash
          : trainerGeohash // ignore: cast_nullable_to_non_nullable
              as String?,
      trainerLocations: null == trainerLocations
          ? _value._trainerLocations
          : trainerLocations // ignore: cast_nullable_to_non_nullable
              as List<TrainerLocation>,
      trainerGeohashes: null == trainerGeohashes
          ? _value._trainerGeohashes
          : trainerGeohashes // ignore: cast_nullable_to_non_nullable
              as List<String>,
      trainerOffersOnline: null == trainerOffersOnline
          ? _value.trainerOffersOnline
          : trainerOffersOnline // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$UserProfileImpl implements _UserProfile {
  const _$UserProfileImpl(
      {required this.uid,
      required this.email,
      required this.displayName,
      required this.role,
      @TimestampConverter() required this.createdAt,
      @TimestampConverter() required this.updatedAt,
      this.gymId,
      this.bodyWeightKg,
      this.heightCm,
      this.gender,
      this.experienceLevel,
      this.avatarUrl,
      @TimestampConverter() this.bornAt,
      this.trainerBio,
      this.trainerSpecialty,
      this.trainerMonthlyRate,
      this.trainerLatitude,
      this.trainerLongitude,
      this.trainerGeohash,
      final List<TrainerLocation> trainerLocations = const <TrainerLocation>[],
      final List<String> trainerGeohashes = const <String>[],
      this.trainerOffersOnline = false})
      : _trainerLocations = trainerLocations,
        _trainerGeohashes = trainerGeohashes;

  factory _$UserProfileImpl.fromJson(Map<String, dynamic> json) =>
      _$$UserProfileImplFromJson(json);

  @override
  final String uid;
  @override
  final String email;
  @override
  final String? displayName;
  @override
  final UserRole role;
  @override
  @TimestampConverter()
  final DateTime createdAt;
  @override
  @TimestampConverter()
  final DateTime updatedAt;
  @override
  final String? gymId;
  @override
  final double? bodyWeightKg;
  @override
  final int? heightCm;
  @override
  final Gender? gender;
  @override
  final ExperienceLevel? experienceLevel;
  @override
  final String? avatarUrl;
  @override
  @TimestampConverter()
  final DateTime? bornAt;
// ── Trainer-specific (Fase 5 Etapa 1 foundations) ───────────────────
  @override
  final String? trainerBio;
  @override
  final String? trainerSpecialty;
  @override
  final int? trainerMonthlyRate;
// ── Multi-location (Fase 6 Etapa 0) ────────────────────────────────
//
// `trainerLatitude/Longitude/Geohash` (singulares, marcados DEPRECATED)
// se mantienen por backward compat — clientes viejos siguen leyendo el
// campo legacy hasta que actualicen. La migration de `treino-dev`
// (scripts/migrate_trainer_locations.js) convierte cada doc legacy a
// `trainerLocations: [{type: custom OR gym, ...}]`. Cleanup PR borra
// los campos legacy cuando todas las clientes estén en la versión nueva.
//
// `trainerLocations` mezcla gyms del catálogo (`type == gym`, `gymId`
// referencia `gyms/{gymId}`) y lugares propios (`type == custom`,
// `customLabel` lleva el nombre).
//
// `trainerGeohashes` es array derivado en write-time desde
// `trainerLocations` — necesario para el query
// `where('trainerGeohashes', array-contains-any, [vecinos del atleta])`
// que reemplaza el `where('trainerGeohash', >=, prefix5)` original.
//
// `trainerOffersOnline` es flag independiente. La combinación
// `trainerLocations.isEmpty && !trainerOffersOnline` es inválida —
// UserRepository.update() la rechaza con ArgumentError antes del write.
  @override
  final double? trainerLatitude;
// DEPRECATED
  @override
  final double? trainerLongitude;
// DEPRECATED
  @override
  final String? trainerGeohash;
// DEPRECATED
  final List<TrainerLocation> _trainerLocations;
// DEPRECATED
  @override
  @JsonKey()
  List<TrainerLocation> get trainerLocations {
    if (_trainerLocations is EqualUnmodifiableListView)
      return _trainerLocations;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_trainerLocations);
  }

  final List<String> _trainerGeohashes;
  @override
  @JsonKey()
  List<String> get trainerGeohashes {
    if (_trainerGeohashes is EqualUnmodifiableListView)
      return _trainerGeohashes;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_trainerGeohashes);
  }

  @override
  @JsonKey()
  final bool trainerOffersOnline;

  @override
  String toString() {
    return 'UserProfile(uid: $uid, email: $email, displayName: $displayName, role: $role, createdAt: $createdAt, updatedAt: $updatedAt, gymId: $gymId, bodyWeightKg: $bodyWeightKg, heightCm: $heightCm, gender: $gender, experienceLevel: $experienceLevel, avatarUrl: $avatarUrl, bornAt: $bornAt, trainerBio: $trainerBio, trainerSpecialty: $trainerSpecialty, trainerMonthlyRate: $trainerMonthlyRate, trainerLatitude: $trainerLatitude, trainerLongitude: $trainerLongitude, trainerGeohash: $trainerGeohash, trainerLocations: $trainerLocations, trainerGeohashes: $trainerGeohashes, trainerOffersOnline: $trainerOffersOnline)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UserProfileImpl &&
            (identical(other.uid, uid) || other.uid == uid) &&
            (identical(other.email, email) || other.email == email) &&
            (identical(other.displayName, displayName) ||
                other.displayName == displayName) &&
            (identical(other.role, role) || other.role == role) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt) &&
            (identical(other.gymId, gymId) || other.gymId == gymId) &&
            (identical(other.bodyWeightKg, bodyWeightKg) ||
                other.bodyWeightKg == bodyWeightKg) &&
            (identical(other.heightCm, heightCm) ||
                other.heightCm == heightCm) &&
            (identical(other.gender, gender) || other.gender == gender) &&
            (identical(other.experienceLevel, experienceLevel) ||
                other.experienceLevel == experienceLevel) &&
            (identical(other.avatarUrl, avatarUrl) ||
                other.avatarUrl == avatarUrl) &&
            (identical(other.bornAt, bornAt) || other.bornAt == bornAt) &&
            (identical(other.trainerBio, trainerBio) ||
                other.trainerBio == trainerBio) &&
            (identical(other.trainerSpecialty, trainerSpecialty) ||
                other.trainerSpecialty == trainerSpecialty) &&
            (identical(other.trainerMonthlyRate, trainerMonthlyRate) ||
                other.trainerMonthlyRate == trainerMonthlyRate) &&
            (identical(other.trainerLatitude, trainerLatitude) ||
                other.trainerLatitude == trainerLatitude) &&
            (identical(other.trainerLongitude, trainerLongitude) ||
                other.trainerLongitude == trainerLongitude) &&
            (identical(other.trainerGeohash, trainerGeohash) ||
                other.trainerGeohash == trainerGeohash) &&
            const DeepCollectionEquality()
                .equals(other._trainerLocations, _trainerLocations) &&
            const DeepCollectionEquality()
                .equals(other._trainerGeohashes, _trainerGeohashes) &&
            (identical(other.trainerOffersOnline, trainerOffersOnline) ||
                other.trainerOffersOnline == trainerOffersOnline));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        uid,
        email,
        displayName,
        role,
        createdAt,
        updatedAt,
        gymId,
        bodyWeightKg,
        heightCm,
        gender,
        experienceLevel,
        avatarUrl,
        bornAt,
        trainerBio,
        trainerSpecialty,
        trainerMonthlyRate,
        trainerLatitude,
        trainerLongitude,
        trainerGeohash,
        const DeepCollectionEquality().hash(_trainerLocations),
        const DeepCollectionEquality().hash(_trainerGeohashes),
        trainerOffersOnline
      ]);

  /// Create a copy of UserProfile
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$UserProfileImplCopyWith<_$UserProfileImpl> get copyWith =>
      __$$UserProfileImplCopyWithImpl<_$UserProfileImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$UserProfileImplToJson(
      this,
    );
  }
}

abstract class _UserProfile implements UserProfile {
  const factory _UserProfile(
      {required final String uid,
      required final String email,
      required final String? displayName,
      required final UserRole role,
      @TimestampConverter() required final DateTime createdAt,
      @TimestampConverter() required final DateTime updatedAt,
      final String? gymId,
      final double? bodyWeightKg,
      final int? heightCm,
      final Gender? gender,
      final ExperienceLevel? experienceLevel,
      final String? avatarUrl,
      @TimestampConverter() final DateTime? bornAt,
      final String? trainerBio,
      final String? trainerSpecialty,
      final int? trainerMonthlyRate,
      final double? trainerLatitude,
      final double? trainerLongitude,
      final String? trainerGeohash,
      final List<TrainerLocation> trainerLocations,
      final List<String> trainerGeohashes,
      final bool trainerOffersOnline}) = _$UserProfileImpl;

  factory _UserProfile.fromJson(Map<String, dynamic> json) =
      _$UserProfileImpl.fromJson;

  @override
  String get uid;
  @override
  String get email;
  @override
  String? get displayName;
  @override
  UserRole get role;
  @override
  @TimestampConverter()
  DateTime get createdAt;
  @override
  @TimestampConverter()
  DateTime get updatedAt;
  @override
  String? get gymId;
  @override
  double? get bodyWeightKg;
  @override
  int? get heightCm;
  @override
  Gender? get gender;
  @override
  ExperienceLevel? get experienceLevel;
  @override
  String? get avatarUrl;
  @override
  @TimestampConverter()
  DateTime?
      get bornAt; // ── Trainer-specific (Fase 5 Etapa 1 foundations) ───────────────────
  @override
  String? get trainerBio;
  @override
  String? get trainerSpecialty;
  @override
  int?
      get trainerMonthlyRate; // ── Multi-location (Fase 6 Etapa 0) ────────────────────────────────
//
// `trainerLatitude/Longitude/Geohash` (singulares, marcados DEPRECATED)
// se mantienen por backward compat — clientes viejos siguen leyendo el
// campo legacy hasta que actualicen. La migration de `treino-dev`
// (scripts/migrate_trainer_locations.js) convierte cada doc legacy a
// `trainerLocations: [{type: custom OR gym, ...}]`. Cleanup PR borra
// los campos legacy cuando todas las clientes estén en la versión nueva.
//
// `trainerLocations` mezcla gyms del catálogo (`type == gym`, `gymId`
// referencia `gyms/{gymId}`) y lugares propios (`type == custom`,
// `customLabel` lleva el nombre).
//
// `trainerGeohashes` es array derivado en write-time desde
// `trainerLocations` — necesario para el query
// `where('trainerGeohashes', array-contains-any, [vecinos del atleta])`
// que reemplaza el `where('trainerGeohash', >=, prefix5)` original.
//
// `trainerOffersOnline` es flag independiente. La combinación
// `trainerLocations.isEmpty && !trainerOffersOnline` es inválida —
// UserRepository.update() la rechaza con ArgumentError antes del write.
  @override
  double? get trainerLatitude; // DEPRECATED
  @override
  double? get trainerLongitude; // DEPRECATED
  @override
  String? get trainerGeohash; // DEPRECATED
  @override
  List<TrainerLocation> get trainerLocations;
  @override
  List<String> get trainerGeohashes;
  @override
  bool get trainerOffersOnline;

  /// Create a copy of UserProfile
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$UserProfileImplCopyWith<_$UserProfileImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
