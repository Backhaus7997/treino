// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'measurement.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Measurement _$MeasurementFromJson(Map<String, dynamic> json) {
  return _Measurement.fromJson(json);
}

/// @nodoc
mixin _$Measurement {
  String get id => throw _privateConstructorUsedError;
  String get athleteId => throw _privateConstructorUsedError;

  /// Trainer uid who logged this measurement.
  String get recordedBy => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get recordedAt =>
      throw _privateConstructorUsedError; // ─── Body composition ────────────────────────────────────────────────
  double? get weightKg => throw _privateConstructorUsedError;
  double? get fatPercentage => throw _privateConstructorUsedError;
  double? get muscleMassKg =>
      throw _privateConstructorUsedError; // ─── Trunk circumferences (cm) ───────────────────────────────────────
  double? get shouldersCm => throw _privateConstructorUsedError;
  double? get chestCm => throw _privateConstructorUsedError;
  double? get waistCm => throw _privateConstructorUsedError;
  double? get hipsCm => throw _privateConstructorUsedError;
  double? get glutesCm =>
      throw _privateConstructorUsedError; // ─── Upper body bilateral (cm) ───────────────────────────────────────
  double? get bicepsLCm => throw _privateConstructorUsedError;
  double? get bicepsRCm => throw _privateConstructorUsedError;
  double? get bicepsFlexedLCm => throw _privateConstructorUsedError;
  double? get bicepsFlexedRCm => throw _privateConstructorUsedError;
  double? get forearmLCm => throw _privateConstructorUsedError;
  double? get forearmRCm =>
      throw _privateConstructorUsedError; // ─── Lower body bilateral (cm) ───────────────────────────────────────
  double? get upperThighLCm => throw _privateConstructorUsedError;
  double? get upperThighRCm => throw _privateConstructorUsedError;
  double? get midThighLCm => throw _privateConstructorUsedError;
  double? get midThighRCm => throw _privateConstructorUsedError;
  double? get calfLCm => throw _privateConstructorUsedError;
  double? get calfRCm =>
      throw _privateConstructorUsedError; // ─── Meta ─────────────────────────────────────────────────────────────
  String? get notes => throw _privateConstructorUsedError;

  /// Serializes this Measurement to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Measurement
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $MeasurementCopyWith<Measurement> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MeasurementCopyWith<$Res> {
  factory $MeasurementCopyWith(
          Measurement value, $Res Function(Measurement) then) =
      _$MeasurementCopyWithImpl<$Res, Measurement>;
  @useResult
  $Res call(
      {String id,
      String athleteId,
      String recordedBy,
      @TimestampConverter() DateTime recordedAt,
      double? weightKg,
      double? fatPercentage,
      double? muscleMassKg,
      double? shouldersCm,
      double? chestCm,
      double? waistCm,
      double? hipsCm,
      double? glutesCm,
      double? bicepsLCm,
      double? bicepsRCm,
      double? bicepsFlexedLCm,
      double? bicepsFlexedRCm,
      double? forearmLCm,
      double? forearmRCm,
      double? upperThighLCm,
      double? upperThighRCm,
      double? midThighLCm,
      double? midThighRCm,
      double? calfLCm,
      double? calfRCm,
      String? notes});
}

/// @nodoc
class _$MeasurementCopyWithImpl<$Res, $Val extends Measurement>
    implements $MeasurementCopyWith<$Res> {
  _$MeasurementCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Measurement
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? athleteId = null,
    Object? recordedBy = null,
    Object? recordedAt = null,
    Object? weightKg = freezed,
    Object? fatPercentage = freezed,
    Object? muscleMassKg = freezed,
    Object? shouldersCm = freezed,
    Object? chestCm = freezed,
    Object? waistCm = freezed,
    Object? hipsCm = freezed,
    Object? glutesCm = freezed,
    Object? bicepsLCm = freezed,
    Object? bicepsRCm = freezed,
    Object? bicepsFlexedLCm = freezed,
    Object? bicepsFlexedRCm = freezed,
    Object? forearmLCm = freezed,
    Object? forearmRCm = freezed,
    Object? upperThighLCm = freezed,
    Object? upperThighRCm = freezed,
    Object? midThighLCm = freezed,
    Object? midThighRCm = freezed,
    Object? calfLCm = freezed,
    Object? calfRCm = freezed,
    Object? notes = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      athleteId: null == athleteId
          ? _value.athleteId
          : athleteId // ignore: cast_nullable_to_non_nullable
              as String,
      recordedBy: null == recordedBy
          ? _value.recordedBy
          : recordedBy // ignore: cast_nullable_to_non_nullable
              as String,
      recordedAt: null == recordedAt
          ? _value.recordedAt
          : recordedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      weightKg: freezed == weightKg
          ? _value.weightKg
          : weightKg // ignore: cast_nullable_to_non_nullable
              as double?,
      fatPercentage: freezed == fatPercentage
          ? _value.fatPercentage
          : fatPercentage // ignore: cast_nullable_to_non_nullable
              as double?,
      muscleMassKg: freezed == muscleMassKg
          ? _value.muscleMassKg
          : muscleMassKg // ignore: cast_nullable_to_non_nullable
              as double?,
      shouldersCm: freezed == shouldersCm
          ? _value.shouldersCm
          : shouldersCm // ignore: cast_nullable_to_non_nullable
              as double?,
      chestCm: freezed == chestCm
          ? _value.chestCm
          : chestCm // ignore: cast_nullable_to_non_nullable
              as double?,
      waistCm: freezed == waistCm
          ? _value.waistCm
          : waistCm // ignore: cast_nullable_to_non_nullable
              as double?,
      hipsCm: freezed == hipsCm
          ? _value.hipsCm
          : hipsCm // ignore: cast_nullable_to_non_nullable
              as double?,
      glutesCm: freezed == glutesCm
          ? _value.glutesCm
          : glutesCm // ignore: cast_nullable_to_non_nullable
              as double?,
      bicepsLCm: freezed == bicepsLCm
          ? _value.bicepsLCm
          : bicepsLCm // ignore: cast_nullable_to_non_nullable
              as double?,
      bicepsRCm: freezed == bicepsRCm
          ? _value.bicepsRCm
          : bicepsRCm // ignore: cast_nullable_to_non_nullable
              as double?,
      bicepsFlexedLCm: freezed == bicepsFlexedLCm
          ? _value.bicepsFlexedLCm
          : bicepsFlexedLCm // ignore: cast_nullable_to_non_nullable
              as double?,
      bicepsFlexedRCm: freezed == bicepsFlexedRCm
          ? _value.bicepsFlexedRCm
          : bicepsFlexedRCm // ignore: cast_nullable_to_non_nullable
              as double?,
      forearmLCm: freezed == forearmLCm
          ? _value.forearmLCm
          : forearmLCm // ignore: cast_nullable_to_non_nullable
              as double?,
      forearmRCm: freezed == forearmRCm
          ? _value.forearmRCm
          : forearmRCm // ignore: cast_nullable_to_non_nullable
              as double?,
      upperThighLCm: freezed == upperThighLCm
          ? _value.upperThighLCm
          : upperThighLCm // ignore: cast_nullable_to_non_nullable
              as double?,
      upperThighRCm: freezed == upperThighRCm
          ? _value.upperThighRCm
          : upperThighRCm // ignore: cast_nullable_to_non_nullable
              as double?,
      midThighLCm: freezed == midThighLCm
          ? _value.midThighLCm
          : midThighLCm // ignore: cast_nullable_to_non_nullable
              as double?,
      midThighRCm: freezed == midThighRCm
          ? _value.midThighRCm
          : midThighRCm // ignore: cast_nullable_to_non_nullable
              as double?,
      calfLCm: freezed == calfLCm
          ? _value.calfLCm
          : calfLCm // ignore: cast_nullable_to_non_nullable
              as double?,
      calfRCm: freezed == calfRCm
          ? _value.calfRCm
          : calfRCm // ignore: cast_nullable_to_non_nullable
              as double?,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$MeasurementImplCopyWith<$Res>
    implements $MeasurementCopyWith<$Res> {
  factory _$$MeasurementImplCopyWith(
          _$MeasurementImpl value, $Res Function(_$MeasurementImpl) then) =
      __$$MeasurementImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String athleteId,
      String recordedBy,
      @TimestampConverter() DateTime recordedAt,
      double? weightKg,
      double? fatPercentage,
      double? muscleMassKg,
      double? shouldersCm,
      double? chestCm,
      double? waistCm,
      double? hipsCm,
      double? glutesCm,
      double? bicepsLCm,
      double? bicepsRCm,
      double? bicepsFlexedLCm,
      double? bicepsFlexedRCm,
      double? forearmLCm,
      double? forearmRCm,
      double? upperThighLCm,
      double? upperThighRCm,
      double? midThighLCm,
      double? midThighRCm,
      double? calfLCm,
      double? calfRCm,
      String? notes});
}

/// @nodoc
class __$$MeasurementImplCopyWithImpl<$Res>
    extends _$MeasurementCopyWithImpl<$Res, _$MeasurementImpl>
    implements _$$MeasurementImplCopyWith<$Res> {
  __$$MeasurementImplCopyWithImpl(
      _$MeasurementImpl _value, $Res Function(_$MeasurementImpl) _then)
      : super(_value, _then);

  /// Create a copy of Measurement
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? athleteId = null,
    Object? recordedBy = null,
    Object? recordedAt = null,
    Object? weightKg = freezed,
    Object? fatPercentage = freezed,
    Object? muscleMassKg = freezed,
    Object? shouldersCm = freezed,
    Object? chestCm = freezed,
    Object? waistCm = freezed,
    Object? hipsCm = freezed,
    Object? glutesCm = freezed,
    Object? bicepsLCm = freezed,
    Object? bicepsRCm = freezed,
    Object? bicepsFlexedLCm = freezed,
    Object? bicepsFlexedRCm = freezed,
    Object? forearmLCm = freezed,
    Object? forearmRCm = freezed,
    Object? upperThighLCm = freezed,
    Object? upperThighRCm = freezed,
    Object? midThighLCm = freezed,
    Object? midThighRCm = freezed,
    Object? calfLCm = freezed,
    Object? calfRCm = freezed,
    Object? notes = freezed,
  }) {
    return _then(_$MeasurementImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      athleteId: null == athleteId
          ? _value.athleteId
          : athleteId // ignore: cast_nullable_to_non_nullable
              as String,
      recordedBy: null == recordedBy
          ? _value.recordedBy
          : recordedBy // ignore: cast_nullable_to_non_nullable
              as String,
      recordedAt: null == recordedAt
          ? _value.recordedAt
          : recordedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      weightKg: freezed == weightKg
          ? _value.weightKg
          : weightKg // ignore: cast_nullable_to_non_nullable
              as double?,
      fatPercentage: freezed == fatPercentage
          ? _value.fatPercentage
          : fatPercentage // ignore: cast_nullable_to_non_nullable
              as double?,
      muscleMassKg: freezed == muscleMassKg
          ? _value.muscleMassKg
          : muscleMassKg // ignore: cast_nullable_to_non_nullable
              as double?,
      shouldersCm: freezed == shouldersCm
          ? _value.shouldersCm
          : shouldersCm // ignore: cast_nullable_to_non_nullable
              as double?,
      chestCm: freezed == chestCm
          ? _value.chestCm
          : chestCm // ignore: cast_nullable_to_non_nullable
              as double?,
      waistCm: freezed == waistCm
          ? _value.waistCm
          : waistCm // ignore: cast_nullable_to_non_nullable
              as double?,
      hipsCm: freezed == hipsCm
          ? _value.hipsCm
          : hipsCm // ignore: cast_nullable_to_non_nullable
              as double?,
      glutesCm: freezed == glutesCm
          ? _value.glutesCm
          : glutesCm // ignore: cast_nullable_to_non_nullable
              as double?,
      bicepsLCm: freezed == bicepsLCm
          ? _value.bicepsLCm
          : bicepsLCm // ignore: cast_nullable_to_non_nullable
              as double?,
      bicepsRCm: freezed == bicepsRCm
          ? _value.bicepsRCm
          : bicepsRCm // ignore: cast_nullable_to_non_nullable
              as double?,
      bicepsFlexedLCm: freezed == bicepsFlexedLCm
          ? _value.bicepsFlexedLCm
          : bicepsFlexedLCm // ignore: cast_nullable_to_non_nullable
              as double?,
      bicepsFlexedRCm: freezed == bicepsFlexedRCm
          ? _value.bicepsFlexedRCm
          : bicepsFlexedRCm // ignore: cast_nullable_to_non_nullable
              as double?,
      forearmLCm: freezed == forearmLCm
          ? _value.forearmLCm
          : forearmLCm // ignore: cast_nullable_to_non_nullable
              as double?,
      forearmRCm: freezed == forearmRCm
          ? _value.forearmRCm
          : forearmRCm // ignore: cast_nullable_to_non_nullable
              as double?,
      upperThighLCm: freezed == upperThighLCm
          ? _value.upperThighLCm
          : upperThighLCm // ignore: cast_nullable_to_non_nullable
              as double?,
      upperThighRCm: freezed == upperThighRCm
          ? _value.upperThighRCm
          : upperThighRCm // ignore: cast_nullable_to_non_nullable
              as double?,
      midThighLCm: freezed == midThighLCm
          ? _value.midThighLCm
          : midThighLCm // ignore: cast_nullable_to_non_nullable
              as double?,
      midThighRCm: freezed == midThighRCm
          ? _value.midThighRCm
          : midThighRCm // ignore: cast_nullable_to_non_nullable
              as double?,
      calfLCm: freezed == calfLCm
          ? _value.calfLCm
          : calfLCm // ignore: cast_nullable_to_non_nullable
              as double?,
      calfRCm: freezed == calfRCm
          ? _value.calfRCm
          : calfRCm // ignore: cast_nullable_to_non_nullable
              as double?,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MeasurementImpl implements _Measurement {
  const _$MeasurementImpl(
      {required this.id,
      required this.athleteId,
      required this.recordedBy,
      @TimestampConverter() required this.recordedAt,
      this.weightKg,
      this.fatPercentage,
      this.muscleMassKg,
      this.shouldersCm,
      this.chestCm,
      this.waistCm,
      this.hipsCm,
      this.glutesCm,
      this.bicepsLCm,
      this.bicepsRCm,
      this.bicepsFlexedLCm,
      this.bicepsFlexedRCm,
      this.forearmLCm,
      this.forearmRCm,
      this.upperThighLCm,
      this.upperThighRCm,
      this.midThighLCm,
      this.midThighRCm,
      this.calfLCm,
      this.calfRCm,
      this.notes});

  factory _$MeasurementImpl.fromJson(Map<String, dynamic> json) =>
      _$$MeasurementImplFromJson(json);

  @override
  final String id;
  @override
  final String athleteId;

  /// Trainer uid who logged this measurement.
  @override
  final String recordedBy;
  @override
  @TimestampConverter()
  final DateTime recordedAt;
// ─── Body composition ────────────────────────────────────────────────
  @override
  final double? weightKg;
  @override
  final double? fatPercentage;
  @override
  final double? muscleMassKg;
// ─── Trunk circumferences (cm) ───────────────────────────────────────
  @override
  final double? shouldersCm;
  @override
  final double? chestCm;
  @override
  final double? waistCm;
  @override
  final double? hipsCm;
  @override
  final double? glutesCm;
// ─── Upper body bilateral (cm) ───────────────────────────────────────
  @override
  final double? bicepsLCm;
  @override
  final double? bicepsRCm;
  @override
  final double? bicepsFlexedLCm;
  @override
  final double? bicepsFlexedRCm;
  @override
  final double? forearmLCm;
  @override
  final double? forearmRCm;
// ─── Lower body bilateral (cm) ───────────────────────────────────────
  @override
  final double? upperThighLCm;
  @override
  final double? upperThighRCm;
  @override
  final double? midThighLCm;
  @override
  final double? midThighRCm;
  @override
  final double? calfLCm;
  @override
  final double? calfRCm;
// ─── Meta ─────────────────────────────────────────────────────────────
  @override
  final String? notes;

  @override
  String toString() {
    return 'Measurement(id: $id, athleteId: $athleteId, recordedBy: $recordedBy, recordedAt: $recordedAt, weightKg: $weightKg, fatPercentage: $fatPercentage, muscleMassKg: $muscleMassKg, shouldersCm: $shouldersCm, chestCm: $chestCm, waistCm: $waistCm, hipsCm: $hipsCm, glutesCm: $glutesCm, bicepsLCm: $bicepsLCm, bicepsRCm: $bicepsRCm, bicepsFlexedLCm: $bicepsFlexedLCm, bicepsFlexedRCm: $bicepsFlexedRCm, forearmLCm: $forearmLCm, forearmRCm: $forearmRCm, upperThighLCm: $upperThighLCm, upperThighRCm: $upperThighRCm, midThighLCm: $midThighLCm, midThighRCm: $midThighRCm, calfLCm: $calfLCm, calfRCm: $calfRCm, notes: $notes)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MeasurementImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.athleteId, athleteId) ||
                other.athleteId == athleteId) &&
            (identical(other.recordedBy, recordedBy) ||
                other.recordedBy == recordedBy) &&
            (identical(other.recordedAt, recordedAt) ||
                other.recordedAt == recordedAt) &&
            (identical(other.weightKg, weightKg) ||
                other.weightKg == weightKg) &&
            (identical(other.fatPercentage, fatPercentage) ||
                other.fatPercentage == fatPercentage) &&
            (identical(other.muscleMassKg, muscleMassKg) ||
                other.muscleMassKg == muscleMassKg) &&
            (identical(other.shouldersCm, shouldersCm) ||
                other.shouldersCm == shouldersCm) &&
            (identical(other.chestCm, chestCm) || other.chestCm == chestCm) &&
            (identical(other.waistCm, waistCm) || other.waistCm == waistCm) &&
            (identical(other.hipsCm, hipsCm) || other.hipsCm == hipsCm) &&
            (identical(other.glutesCm, glutesCm) ||
                other.glutesCm == glutesCm) &&
            (identical(other.bicepsLCm, bicepsLCm) ||
                other.bicepsLCm == bicepsLCm) &&
            (identical(other.bicepsRCm, bicepsRCm) ||
                other.bicepsRCm == bicepsRCm) &&
            (identical(other.bicepsFlexedLCm, bicepsFlexedLCm) ||
                other.bicepsFlexedLCm == bicepsFlexedLCm) &&
            (identical(other.bicepsFlexedRCm, bicepsFlexedRCm) ||
                other.bicepsFlexedRCm == bicepsFlexedRCm) &&
            (identical(other.forearmLCm, forearmLCm) ||
                other.forearmLCm == forearmLCm) &&
            (identical(other.forearmRCm, forearmRCm) ||
                other.forearmRCm == forearmRCm) &&
            (identical(other.upperThighLCm, upperThighLCm) ||
                other.upperThighLCm == upperThighLCm) &&
            (identical(other.upperThighRCm, upperThighRCm) ||
                other.upperThighRCm == upperThighRCm) &&
            (identical(other.midThighLCm, midThighLCm) ||
                other.midThighLCm == midThighLCm) &&
            (identical(other.midThighRCm, midThighRCm) ||
                other.midThighRCm == midThighRCm) &&
            (identical(other.calfLCm, calfLCm) || other.calfLCm == calfLCm) &&
            (identical(other.calfRCm, calfRCm) || other.calfRCm == calfRCm) &&
            (identical(other.notes, notes) || other.notes == notes));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        id,
        athleteId,
        recordedBy,
        recordedAt,
        weightKg,
        fatPercentage,
        muscleMassKg,
        shouldersCm,
        chestCm,
        waistCm,
        hipsCm,
        glutesCm,
        bicepsLCm,
        bicepsRCm,
        bicepsFlexedLCm,
        bicepsFlexedRCm,
        forearmLCm,
        forearmRCm,
        upperThighLCm,
        upperThighRCm,
        midThighLCm,
        midThighRCm,
        calfLCm,
        calfRCm,
        notes
      ]);

  /// Create a copy of Measurement
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MeasurementImplCopyWith<_$MeasurementImpl> get copyWith =>
      __$$MeasurementImplCopyWithImpl<_$MeasurementImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$MeasurementImplToJson(
      this,
    );
  }
}

abstract class _Measurement implements Measurement {
  const factory _Measurement(
      {required final String id,
      required final String athleteId,
      required final String recordedBy,
      @TimestampConverter() required final DateTime recordedAt,
      final double? weightKg,
      final double? fatPercentage,
      final double? muscleMassKg,
      final double? shouldersCm,
      final double? chestCm,
      final double? waistCm,
      final double? hipsCm,
      final double? glutesCm,
      final double? bicepsLCm,
      final double? bicepsRCm,
      final double? bicepsFlexedLCm,
      final double? bicepsFlexedRCm,
      final double? forearmLCm,
      final double? forearmRCm,
      final double? upperThighLCm,
      final double? upperThighRCm,
      final double? midThighLCm,
      final double? midThighRCm,
      final double? calfLCm,
      final double? calfRCm,
      final String? notes}) = _$MeasurementImpl;

  factory _Measurement.fromJson(Map<String, dynamic> json) =
      _$MeasurementImpl.fromJson;

  @override
  String get id;
  @override
  String get athleteId;

  /// Trainer uid who logged this measurement.
  @override
  String get recordedBy;
  @override
  @TimestampConverter()
  DateTime
      get recordedAt; // ─── Body composition ────────────────────────────────────────────────
  @override
  double? get weightKg;
  @override
  double? get fatPercentage;
  @override
  double?
      get muscleMassKg; // ─── Trunk circumferences (cm) ───────────────────────────────────────
  @override
  double? get shouldersCm;
  @override
  double? get chestCm;
  @override
  double? get waistCm;
  @override
  double? get hipsCm;
  @override
  double?
      get glutesCm; // ─── Upper body bilateral (cm) ───────────────────────────────────────
  @override
  double? get bicepsLCm;
  @override
  double? get bicepsRCm;
  @override
  double? get bicepsFlexedLCm;
  @override
  double? get bicepsFlexedRCm;
  @override
  double? get forearmLCm;
  @override
  double?
      get forearmRCm; // ─── Lower body bilateral (cm) ───────────────────────────────────────
  @override
  double? get upperThighLCm;
  @override
  double? get upperThighRCm;
  @override
  double? get midThighLCm;
  @override
  double? get midThighRCm;
  @override
  double? get calfLCm;
  @override
  double?
      get calfRCm; // ─── Meta ─────────────────────────────────────────────────────────────
  @override
  String? get notes;

  /// Create a copy of Measurement
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MeasurementImplCopyWith<_$MeasurementImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
