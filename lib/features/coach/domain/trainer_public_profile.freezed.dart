// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'trainer_public_profile.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

TrainerPublicProfile _$TrainerPublicProfileFromJson(Map<String, dynamic> json) {
  return _TrainerPublicProfile.fromJson(json);
}

/// @nodoc
mixin _$TrainerPublicProfile {
  String get uid => throw _privateConstructorUsedError;
  String? get displayName => throw _privateConstructorUsedError;
  String? get displayNameLowercase => throw _privateConstructorUsedError;
  String? get avatarUrl => throw _privateConstructorUsedError;
  String? get trainerBio => throw _privateConstructorUsedError;
  @JsonKey(fromJson: _specialtyFromJson, toJson: _specialtyToJson)
  TrainerSpecialty? get trainerSpecialty =>
      throw _privateConstructorUsedError; // DEPRECATED — singular location campos legacy. Mantenidos por backward
// compat hasta el cleanup PR. Ver doc del campo equivalente en UserProfile.
  String? get trainerGeohash => throw _privateConstructorUsedError;
  double? get trainerLatitude => throw _privateConstructorUsedError;
  double? get trainerLongitude => throw _privateConstructorUsedError;
  int? get trainerMonthlyRate => throw _privateConstructorUsedError;
  String? get paymentAlias =>
      throw _privateConstructorUsedError; // ── Multi-location (Fase 6 Etapa 0) ────────────────────────────────
  List<TrainerLocation> get trainerLocations =>
      throw _privateConstructorUsedError;
  List<String> get trainerGeohashes => throw _privateConstructorUsedError;
  bool get trainerOffersOnline =>
      throw _privateConstructorUsedError; // ── Review aggregate (Fase 6 Etapa 7) ──────────────────────────────────
// Written exclusively by the reviewAggregate Cloud Function.
// ADR-RV-004: lives on TrainerPublicProfile for O(1) discovery reads.
// ADR-RV-005: MUST NOT appear in UserRepository._trainerPublicFields.
  double? get averageRating => throw _privateConstructorUsedError;
  int get reviewCount =>
      throw _privateConstructorUsedError; // ── Stats reales del perfil público (#388) ─────────────────────────────
// `trainerExperienceYears` es self-attested: lo edita el PF en su form y
// llega acá vía el dual-write de UserRepository (como trainerBio).
// `athleteCount` es un agregado derivado (count de trainer_links activos),
// escrito exclusivamente por el linkAggregate Cloud Function — mismo
// contrato que averageRating/reviewCount: MUST NOT aparecer en
// UserRepository._trainerPublicFields ni ser escribible por el cliente
// (pin en firestore.rules). Null ⇒ nunca computado → la UI muestra "—".
  int? get trainerExperienceYears => throw _privateConstructorUsedError;
  int? get athleteCount => throw _privateConstructorUsedError;

  /// Serializes this TrainerPublicProfile to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of TrainerPublicProfile
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $TrainerPublicProfileCopyWith<TrainerPublicProfile> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TrainerPublicProfileCopyWith<$Res> {
  factory $TrainerPublicProfileCopyWith(TrainerPublicProfile value,
          $Res Function(TrainerPublicProfile) then) =
      _$TrainerPublicProfileCopyWithImpl<$Res, TrainerPublicProfile>;
  @useResult
  $Res call(
      {String uid,
      String? displayName,
      String? displayNameLowercase,
      String? avatarUrl,
      String? trainerBio,
      @JsonKey(fromJson: _specialtyFromJson, toJson: _specialtyToJson)
      TrainerSpecialty? trainerSpecialty,
      String? trainerGeohash,
      double? trainerLatitude,
      double? trainerLongitude,
      int? trainerMonthlyRate,
      String? paymentAlias,
      List<TrainerLocation> trainerLocations,
      List<String> trainerGeohashes,
      bool trainerOffersOnline,
      double? averageRating,
      int reviewCount,
      int? trainerExperienceYears,
      int? athleteCount});
}

/// @nodoc
class _$TrainerPublicProfileCopyWithImpl<$Res,
        $Val extends TrainerPublicProfile>
    implements $TrainerPublicProfileCopyWith<$Res> {
  _$TrainerPublicProfileCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of TrainerPublicProfile
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? uid = null,
    Object? displayName = freezed,
    Object? displayNameLowercase = freezed,
    Object? avatarUrl = freezed,
    Object? trainerBio = freezed,
    Object? trainerSpecialty = freezed,
    Object? trainerGeohash = freezed,
    Object? trainerLatitude = freezed,
    Object? trainerLongitude = freezed,
    Object? trainerMonthlyRate = freezed,
    Object? paymentAlias = freezed,
    Object? trainerLocations = null,
    Object? trainerGeohashes = null,
    Object? trainerOffersOnline = null,
    Object? averageRating = freezed,
    Object? reviewCount = null,
    Object? trainerExperienceYears = freezed,
    Object? athleteCount = freezed,
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
      trainerBio: freezed == trainerBio
          ? _value.trainerBio
          : trainerBio // ignore: cast_nullable_to_non_nullable
              as String?,
      trainerSpecialty: freezed == trainerSpecialty
          ? _value.trainerSpecialty
          : trainerSpecialty // ignore: cast_nullable_to_non_nullable
              as TrainerSpecialty?,
      trainerGeohash: freezed == trainerGeohash
          ? _value.trainerGeohash
          : trainerGeohash // ignore: cast_nullable_to_non_nullable
              as String?,
      trainerLatitude: freezed == trainerLatitude
          ? _value.trainerLatitude
          : trainerLatitude // ignore: cast_nullable_to_non_nullable
              as double?,
      trainerLongitude: freezed == trainerLongitude
          ? _value.trainerLongitude
          : trainerLongitude // ignore: cast_nullable_to_non_nullable
              as double?,
      trainerMonthlyRate: freezed == trainerMonthlyRate
          ? _value.trainerMonthlyRate
          : trainerMonthlyRate // ignore: cast_nullable_to_non_nullable
              as int?,
      paymentAlias: freezed == paymentAlias
          ? _value.paymentAlias
          : paymentAlias // ignore: cast_nullable_to_non_nullable
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
      averageRating: freezed == averageRating
          ? _value.averageRating
          : averageRating // ignore: cast_nullable_to_non_nullable
              as double?,
      reviewCount: null == reviewCount
          ? _value.reviewCount
          : reviewCount // ignore: cast_nullable_to_non_nullable
              as int,
      trainerExperienceYears: freezed == trainerExperienceYears
          ? _value.trainerExperienceYears
          : trainerExperienceYears // ignore: cast_nullable_to_non_nullable
              as int?,
      athleteCount: freezed == athleteCount
          ? _value.athleteCount
          : athleteCount // ignore: cast_nullable_to_non_nullable
              as int?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$TrainerPublicProfileImplCopyWith<$Res>
    implements $TrainerPublicProfileCopyWith<$Res> {
  factory _$$TrainerPublicProfileImplCopyWith(_$TrainerPublicProfileImpl value,
          $Res Function(_$TrainerPublicProfileImpl) then) =
      __$$TrainerPublicProfileImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String uid,
      String? displayName,
      String? displayNameLowercase,
      String? avatarUrl,
      String? trainerBio,
      @JsonKey(fromJson: _specialtyFromJson, toJson: _specialtyToJson)
      TrainerSpecialty? trainerSpecialty,
      String? trainerGeohash,
      double? trainerLatitude,
      double? trainerLongitude,
      int? trainerMonthlyRate,
      String? paymentAlias,
      List<TrainerLocation> trainerLocations,
      List<String> trainerGeohashes,
      bool trainerOffersOnline,
      double? averageRating,
      int reviewCount,
      int? trainerExperienceYears,
      int? athleteCount});
}

/// @nodoc
class __$$TrainerPublicProfileImplCopyWithImpl<$Res>
    extends _$TrainerPublicProfileCopyWithImpl<$Res, _$TrainerPublicProfileImpl>
    implements _$$TrainerPublicProfileImplCopyWith<$Res> {
  __$$TrainerPublicProfileImplCopyWithImpl(_$TrainerPublicProfileImpl _value,
      $Res Function(_$TrainerPublicProfileImpl) _then)
      : super(_value, _then);

  /// Create a copy of TrainerPublicProfile
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? uid = null,
    Object? displayName = freezed,
    Object? displayNameLowercase = freezed,
    Object? avatarUrl = freezed,
    Object? trainerBio = freezed,
    Object? trainerSpecialty = freezed,
    Object? trainerGeohash = freezed,
    Object? trainerLatitude = freezed,
    Object? trainerLongitude = freezed,
    Object? trainerMonthlyRate = freezed,
    Object? paymentAlias = freezed,
    Object? trainerLocations = null,
    Object? trainerGeohashes = null,
    Object? trainerOffersOnline = null,
    Object? averageRating = freezed,
    Object? reviewCount = null,
    Object? trainerExperienceYears = freezed,
    Object? athleteCount = freezed,
  }) {
    return _then(_$TrainerPublicProfileImpl(
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
      trainerBio: freezed == trainerBio
          ? _value.trainerBio
          : trainerBio // ignore: cast_nullable_to_non_nullable
              as String?,
      trainerSpecialty: freezed == trainerSpecialty
          ? _value.trainerSpecialty
          : trainerSpecialty // ignore: cast_nullable_to_non_nullable
              as TrainerSpecialty?,
      trainerGeohash: freezed == trainerGeohash
          ? _value.trainerGeohash
          : trainerGeohash // ignore: cast_nullable_to_non_nullable
              as String?,
      trainerLatitude: freezed == trainerLatitude
          ? _value.trainerLatitude
          : trainerLatitude // ignore: cast_nullable_to_non_nullable
              as double?,
      trainerLongitude: freezed == trainerLongitude
          ? _value.trainerLongitude
          : trainerLongitude // ignore: cast_nullable_to_non_nullable
              as double?,
      trainerMonthlyRate: freezed == trainerMonthlyRate
          ? _value.trainerMonthlyRate
          : trainerMonthlyRate // ignore: cast_nullable_to_non_nullable
              as int?,
      paymentAlias: freezed == paymentAlias
          ? _value.paymentAlias
          : paymentAlias // ignore: cast_nullable_to_non_nullable
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
      averageRating: freezed == averageRating
          ? _value.averageRating
          : averageRating // ignore: cast_nullable_to_non_nullable
              as double?,
      reviewCount: null == reviewCount
          ? _value.reviewCount
          : reviewCount // ignore: cast_nullable_to_non_nullable
              as int,
      trainerExperienceYears: freezed == trainerExperienceYears
          ? _value.trainerExperienceYears
          : trainerExperienceYears // ignore: cast_nullable_to_non_nullable
              as int?,
      athleteCount: freezed == athleteCount
          ? _value.athleteCount
          : athleteCount // ignore: cast_nullable_to_non_nullable
              as int?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$TrainerPublicProfileImpl implements _TrainerPublicProfile {
  const _$TrainerPublicProfileImpl(
      {required this.uid,
      this.displayName,
      this.displayNameLowercase,
      this.avatarUrl,
      this.trainerBio,
      @JsonKey(fromJson: _specialtyFromJson, toJson: _specialtyToJson)
      this.trainerSpecialty,
      this.trainerGeohash,
      this.trainerLatitude,
      this.trainerLongitude,
      this.trainerMonthlyRate,
      this.paymentAlias,
      final List<TrainerLocation> trainerLocations = const <TrainerLocation>[],
      final List<String> trainerGeohashes = const <String>[],
      this.trainerOffersOnline = false,
      this.averageRating,
      this.reviewCount = 0,
      this.trainerExperienceYears,
      this.athleteCount})
      : _trainerLocations = trainerLocations,
        _trainerGeohashes = trainerGeohashes;

  factory _$TrainerPublicProfileImpl.fromJson(Map<String, dynamic> json) =>
      _$$TrainerPublicProfileImplFromJson(json);

  @override
  final String uid;
  @override
  final String? displayName;
  @override
  final String? displayNameLowercase;
  @override
  final String? avatarUrl;
  @override
  final String? trainerBio;
  @override
  @JsonKey(fromJson: _specialtyFromJson, toJson: _specialtyToJson)
  final TrainerSpecialty? trainerSpecialty;
// DEPRECATED — singular location campos legacy. Mantenidos por backward
// compat hasta el cleanup PR. Ver doc del campo equivalente en UserProfile.
  @override
  final String? trainerGeohash;
  @override
  final double? trainerLatitude;
  @override
  final double? trainerLongitude;
  @override
  final int? trainerMonthlyRate;
  @override
  final String? paymentAlias;
// ── Multi-location (Fase 6 Etapa 0) ────────────────────────────────
  final List<TrainerLocation> _trainerLocations;
// ── Multi-location (Fase 6 Etapa 0) ────────────────────────────────
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
// ── Review aggregate (Fase 6 Etapa 7) ──────────────────────────────────
// Written exclusively by the reviewAggregate Cloud Function.
// ADR-RV-004: lives on TrainerPublicProfile for O(1) discovery reads.
// ADR-RV-005: MUST NOT appear in UserRepository._trainerPublicFields.
  @override
  final double? averageRating;
  @override
  @JsonKey()
  final int reviewCount;
// ── Stats reales del perfil público (#388) ─────────────────────────────
// `trainerExperienceYears` es self-attested: lo edita el PF en su form y
// llega acá vía el dual-write de UserRepository (como trainerBio).
// `athleteCount` es un agregado derivado (count de trainer_links activos),
// escrito exclusivamente por el linkAggregate Cloud Function — mismo
// contrato que averageRating/reviewCount: MUST NOT aparecer en
// UserRepository._trainerPublicFields ni ser escribible por el cliente
// (pin en firestore.rules). Null ⇒ nunca computado → la UI muestra "—".
  @override
  final int? trainerExperienceYears;
  @override
  final int? athleteCount;

  @override
  String toString() {
    return 'TrainerPublicProfile(uid: $uid, displayName: $displayName, displayNameLowercase: $displayNameLowercase, avatarUrl: $avatarUrl, trainerBio: $trainerBio, trainerSpecialty: $trainerSpecialty, trainerGeohash: $trainerGeohash, trainerLatitude: $trainerLatitude, trainerLongitude: $trainerLongitude, trainerMonthlyRate: $trainerMonthlyRate, paymentAlias: $paymentAlias, trainerLocations: $trainerLocations, trainerGeohashes: $trainerGeohashes, trainerOffersOnline: $trainerOffersOnline, averageRating: $averageRating, reviewCount: $reviewCount, trainerExperienceYears: $trainerExperienceYears, athleteCount: $athleteCount)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TrainerPublicProfileImpl &&
            (identical(other.uid, uid) || other.uid == uid) &&
            (identical(other.displayName, displayName) ||
                other.displayName == displayName) &&
            (identical(other.displayNameLowercase, displayNameLowercase) ||
                other.displayNameLowercase == displayNameLowercase) &&
            (identical(other.avatarUrl, avatarUrl) ||
                other.avatarUrl == avatarUrl) &&
            (identical(other.trainerBio, trainerBio) ||
                other.trainerBio == trainerBio) &&
            (identical(other.trainerSpecialty, trainerSpecialty) ||
                other.trainerSpecialty == trainerSpecialty) &&
            (identical(other.trainerGeohash, trainerGeohash) ||
                other.trainerGeohash == trainerGeohash) &&
            (identical(other.trainerLatitude, trainerLatitude) ||
                other.trainerLatitude == trainerLatitude) &&
            (identical(other.trainerLongitude, trainerLongitude) ||
                other.trainerLongitude == trainerLongitude) &&
            (identical(other.trainerMonthlyRate, trainerMonthlyRate) ||
                other.trainerMonthlyRate == trainerMonthlyRate) &&
            (identical(other.paymentAlias, paymentAlias) ||
                other.paymentAlias == paymentAlias) &&
            const DeepCollectionEquality()
                .equals(other._trainerLocations, _trainerLocations) &&
            const DeepCollectionEquality()
                .equals(other._trainerGeohashes, _trainerGeohashes) &&
            (identical(other.trainerOffersOnline, trainerOffersOnline) ||
                other.trainerOffersOnline == trainerOffersOnline) &&
            (identical(other.averageRating, averageRating) ||
                other.averageRating == averageRating) &&
            (identical(other.reviewCount, reviewCount) ||
                other.reviewCount == reviewCount) &&
            (identical(other.trainerExperienceYears, trainerExperienceYears) ||
                other.trainerExperienceYears == trainerExperienceYears) &&
            (identical(other.athleteCount, athleteCount) ||
                other.athleteCount == athleteCount));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      uid,
      displayName,
      displayNameLowercase,
      avatarUrl,
      trainerBio,
      trainerSpecialty,
      trainerGeohash,
      trainerLatitude,
      trainerLongitude,
      trainerMonthlyRate,
      paymentAlias,
      const DeepCollectionEquality().hash(_trainerLocations),
      const DeepCollectionEquality().hash(_trainerGeohashes),
      trainerOffersOnline,
      averageRating,
      reviewCount,
      trainerExperienceYears,
      athleteCount);

  /// Create a copy of TrainerPublicProfile
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TrainerPublicProfileImplCopyWith<_$TrainerPublicProfileImpl>
      get copyWith =>
          __$$TrainerPublicProfileImplCopyWithImpl<_$TrainerPublicProfileImpl>(
              this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$TrainerPublicProfileImplToJson(
      this,
    );
  }
}

abstract class _TrainerPublicProfile implements TrainerPublicProfile {
  const factory _TrainerPublicProfile(
      {required final String uid,
      final String? displayName,
      final String? displayNameLowercase,
      final String? avatarUrl,
      final String? trainerBio,
      @JsonKey(fromJson: _specialtyFromJson, toJson: _specialtyToJson)
      final TrainerSpecialty? trainerSpecialty,
      final String? trainerGeohash,
      final double? trainerLatitude,
      final double? trainerLongitude,
      final int? trainerMonthlyRate,
      final String? paymentAlias,
      final List<TrainerLocation> trainerLocations,
      final List<String> trainerGeohashes,
      final bool trainerOffersOnline,
      final double? averageRating,
      final int reviewCount,
      final int? trainerExperienceYears,
      final int? athleteCount}) = _$TrainerPublicProfileImpl;

  factory _TrainerPublicProfile.fromJson(Map<String, dynamic> json) =
      _$TrainerPublicProfileImpl.fromJson;

  @override
  String get uid;
  @override
  String? get displayName;
  @override
  String? get displayNameLowercase;
  @override
  String? get avatarUrl;
  @override
  String? get trainerBio;
  @override
  @JsonKey(fromJson: _specialtyFromJson, toJson: _specialtyToJson)
  TrainerSpecialty?
      get trainerSpecialty; // DEPRECATED — singular location campos legacy. Mantenidos por backward
// compat hasta el cleanup PR. Ver doc del campo equivalente en UserProfile.
  @override
  String? get trainerGeohash;
  @override
  double? get trainerLatitude;
  @override
  double? get trainerLongitude;
  @override
  int? get trainerMonthlyRate;
  @override
  String?
      get paymentAlias; // ── Multi-location (Fase 6 Etapa 0) ────────────────────────────────
  @override
  List<TrainerLocation> get trainerLocations;
  @override
  List<String> get trainerGeohashes;
  @override
  bool
      get trainerOffersOnline; // ── Review aggregate (Fase 6 Etapa 7) ──────────────────────────────────
// Written exclusively by the reviewAggregate Cloud Function.
// ADR-RV-004: lives on TrainerPublicProfile for O(1) discovery reads.
// ADR-RV-005: MUST NOT appear in UserRepository._trainerPublicFields.
  @override
  double? get averageRating;
  @override
  int get reviewCount; // ── Stats reales del perfil público (#388) ─────────────────────────────
// `trainerExperienceYears` es self-attested: lo edita el PF en su form y
// llega acá vía el dual-write de UserRepository (como trainerBio).
// `athleteCount` es un agregado derivado (count de trainer_links activos),
// escrito exclusivamente por el linkAggregate Cloud Function — mismo
// contrato que averageRating/reviewCount: MUST NOT aparecer en
// UserRepository._trainerPublicFields ni ser escribible por el cliente
// (pin en firestore.rules). Null ⇒ nunca computado → la UI muestra "—".
  @override
  int? get trainerExperienceYears;
  @override
  int? get athleteCount;

  /// Create a copy of TrainerPublicProfile
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TrainerPublicProfileImplCopyWith<_$TrainerPublicProfileImpl>
      get copyWith => throw _privateConstructorUsedError;
}
