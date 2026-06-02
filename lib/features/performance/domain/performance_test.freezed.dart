// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'performance_test.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

PerformanceTest _$PerformanceTestFromJson(Map<String, dynamic> json) {
  return _PerformanceTest.fromJson(json);
}

/// @nodoc
mixin _$PerformanceTest {
  String get id => throw _privateConstructorUsedError;
  String get athleteId => throw _privateConstructorUsedError;

  /// Trainer uid who logged this performance test.
  String get recordedBy => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get recordedAt =>
      throw _privateConstructorUsedError; // ─── Saltos (cm) ─────────────────────────────────────────────────────────
  double? get cmjCm => throw _privateConstructorUsedError;
  double? get squatJumpCm => throw _privateConstructorUsedError;
  double? get abalakovCm => throw _privateConstructorUsedError;
  double? get broadJumpCm =>
      throw _privateConstructorUsedError; // ─── Velocidad / sprints (segundos) ──────────────────────────────────────
  double? get sprint10mS => throw _privateConstructorUsedError;
  double? get sprint20mS => throw _privateConstructorUsedError;
  double? get sprint30mS => throw _privateConstructorUsedError;
  double? get sprint40mS =>
      throw _privateConstructorUsedError; // ─── Fuerza máxima 1RM (kg) ──────────────────────────────────────────────
  double? get squat1rmKg => throw _privateConstructorUsedError;
  double? get benchPress1rmKg => throw _privateConstructorUsedError;
  double? get deadlift1rmKg => throw _privateConstructorUsedError;
  double? get overheadPress1rmKg => throw _privateConstructorUsedError;
  double? get pullUp1rmKg =>
      throw _privateConstructorUsedError; // ─── Resistencia / otros ─────────────────────────────────────────────────
  double? get vo2maxMlKgMin => throw _privateConstructorUsedError;
  double? get courseNavetteLevel => throw _privateConstructorUsedError;
  double? get cooperMeters => throw _privateConstructorUsedError;
  double? get sitAndReachCm =>
      throw _privateConstructorUsedError; // ─── Meta ─────────────────────────────────────────────────────────────────
  String? get notes => throw _privateConstructorUsedError;

  /// Serializes this PerformanceTest to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of PerformanceTest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PerformanceTestCopyWith<PerformanceTest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PerformanceTestCopyWith<$Res> {
  factory $PerformanceTestCopyWith(
          PerformanceTest value, $Res Function(PerformanceTest) then) =
      _$PerformanceTestCopyWithImpl<$Res, PerformanceTest>;
  @useResult
  $Res call(
      {String id,
      String athleteId,
      String recordedBy,
      @TimestampConverter() DateTime recordedAt,
      double? cmjCm,
      double? squatJumpCm,
      double? abalakovCm,
      double? broadJumpCm,
      double? sprint10mS,
      double? sprint20mS,
      double? sprint30mS,
      double? sprint40mS,
      double? squat1rmKg,
      double? benchPress1rmKg,
      double? deadlift1rmKg,
      double? overheadPress1rmKg,
      double? pullUp1rmKg,
      double? vo2maxMlKgMin,
      double? courseNavetteLevel,
      double? cooperMeters,
      double? sitAndReachCm,
      String? notes});
}

/// @nodoc
class _$PerformanceTestCopyWithImpl<$Res, $Val extends PerformanceTest>
    implements $PerformanceTestCopyWith<$Res> {
  _$PerformanceTestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PerformanceTest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? athleteId = null,
    Object? recordedBy = null,
    Object? recordedAt = null,
    Object? cmjCm = freezed,
    Object? squatJumpCm = freezed,
    Object? abalakovCm = freezed,
    Object? broadJumpCm = freezed,
    Object? sprint10mS = freezed,
    Object? sprint20mS = freezed,
    Object? sprint30mS = freezed,
    Object? sprint40mS = freezed,
    Object? squat1rmKg = freezed,
    Object? benchPress1rmKg = freezed,
    Object? deadlift1rmKg = freezed,
    Object? overheadPress1rmKg = freezed,
    Object? pullUp1rmKg = freezed,
    Object? vo2maxMlKgMin = freezed,
    Object? courseNavetteLevel = freezed,
    Object? cooperMeters = freezed,
    Object? sitAndReachCm = freezed,
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
      cmjCm: freezed == cmjCm
          ? _value.cmjCm
          : cmjCm // ignore: cast_nullable_to_non_nullable
              as double?,
      squatJumpCm: freezed == squatJumpCm
          ? _value.squatJumpCm
          : squatJumpCm // ignore: cast_nullable_to_non_nullable
              as double?,
      abalakovCm: freezed == abalakovCm
          ? _value.abalakovCm
          : abalakovCm // ignore: cast_nullable_to_non_nullable
              as double?,
      broadJumpCm: freezed == broadJumpCm
          ? _value.broadJumpCm
          : broadJumpCm // ignore: cast_nullable_to_non_nullable
              as double?,
      sprint10mS: freezed == sprint10mS
          ? _value.sprint10mS
          : sprint10mS // ignore: cast_nullable_to_non_nullable
              as double?,
      sprint20mS: freezed == sprint20mS
          ? _value.sprint20mS
          : sprint20mS // ignore: cast_nullable_to_non_nullable
              as double?,
      sprint30mS: freezed == sprint30mS
          ? _value.sprint30mS
          : sprint30mS // ignore: cast_nullable_to_non_nullable
              as double?,
      sprint40mS: freezed == sprint40mS
          ? _value.sprint40mS
          : sprint40mS // ignore: cast_nullable_to_non_nullable
              as double?,
      squat1rmKg: freezed == squat1rmKg
          ? _value.squat1rmKg
          : squat1rmKg // ignore: cast_nullable_to_non_nullable
              as double?,
      benchPress1rmKg: freezed == benchPress1rmKg
          ? _value.benchPress1rmKg
          : benchPress1rmKg // ignore: cast_nullable_to_non_nullable
              as double?,
      deadlift1rmKg: freezed == deadlift1rmKg
          ? _value.deadlift1rmKg
          : deadlift1rmKg // ignore: cast_nullable_to_non_nullable
              as double?,
      overheadPress1rmKg: freezed == overheadPress1rmKg
          ? _value.overheadPress1rmKg
          : overheadPress1rmKg // ignore: cast_nullable_to_non_nullable
              as double?,
      pullUp1rmKg: freezed == pullUp1rmKg
          ? _value.pullUp1rmKg
          : pullUp1rmKg // ignore: cast_nullable_to_non_nullable
              as double?,
      vo2maxMlKgMin: freezed == vo2maxMlKgMin
          ? _value.vo2maxMlKgMin
          : vo2maxMlKgMin // ignore: cast_nullable_to_non_nullable
              as double?,
      courseNavetteLevel: freezed == courseNavetteLevel
          ? _value.courseNavetteLevel
          : courseNavetteLevel // ignore: cast_nullable_to_non_nullable
              as double?,
      cooperMeters: freezed == cooperMeters
          ? _value.cooperMeters
          : cooperMeters // ignore: cast_nullable_to_non_nullable
              as double?,
      sitAndReachCm: freezed == sitAndReachCm
          ? _value.sitAndReachCm
          : sitAndReachCm // ignore: cast_nullable_to_non_nullable
              as double?,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PerformanceTestImplCopyWith<$Res>
    implements $PerformanceTestCopyWith<$Res> {
  factory _$$PerformanceTestImplCopyWith(_$PerformanceTestImpl value,
          $Res Function(_$PerformanceTestImpl) then) =
      __$$PerformanceTestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String athleteId,
      String recordedBy,
      @TimestampConverter() DateTime recordedAt,
      double? cmjCm,
      double? squatJumpCm,
      double? abalakovCm,
      double? broadJumpCm,
      double? sprint10mS,
      double? sprint20mS,
      double? sprint30mS,
      double? sprint40mS,
      double? squat1rmKg,
      double? benchPress1rmKg,
      double? deadlift1rmKg,
      double? overheadPress1rmKg,
      double? pullUp1rmKg,
      double? vo2maxMlKgMin,
      double? courseNavetteLevel,
      double? cooperMeters,
      double? sitAndReachCm,
      String? notes});
}

/// @nodoc
class __$$PerformanceTestImplCopyWithImpl<$Res>
    extends _$PerformanceTestCopyWithImpl<$Res, _$PerformanceTestImpl>
    implements _$$PerformanceTestImplCopyWith<$Res> {
  __$$PerformanceTestImplCopyWithImpl(
      _$PerformanceTestImpl _value, $Res Function(_$PerformanceTestImpl) _then)
      : super(_value, _then);

  /// Create a copy of PerformanceTest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? athleteId = null,
    Object? recordedBy = null,
    Object? recordedAt = null,
    Object? cmjCm = freezed,
    Object? squatJumpCm = freezed,
    Object? abalakovCm = freezed,
    Object? broadJumpCm = freezed,
    Object? sprint10mS = freezed,
    Object? sprint20mS = freezed,
    Object? sprint30mS = freezed,
    Object? sprint40mS = freezed,
    Object? squat1rmKg = freezed,
    Object? benchPress1rmKg = freezed,
    Object? deadlift1rmKg = freezed,
    Object? overheadPress1rmKg = freezed,
    Object? pullUp1rmKg = freezed,
    Object? vo2maxMlKgMin = freezed,
    Object? courseNavetteLevel = freezed,
    Object? cooperMeters = freezed,
    Object? sitAndReachCm = freezed,
    Object? notes = freezed,
  }) {
    return _then(_$PerformanceTestImpl(
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
      cmjCm: freezed == cmjCm
          ? _value.cmjCm
          : cmjCm // ignore: cast_nullable_to_non_nullable
              as double?,
      squatJumpCm: freezed == squatJumpCm
          ? _value.squatJumpCm
          : squatJumpCm // ignore: cast_nullable_to_non_nullable
              as double?,
      abalakovCm: freezed == abalakovCm
          ? _value.abalakovCm
          : abalakovCm // ignore: cast_nullable_to_non_nullable
              as double?,
      broadJumpCm: freezed == broadJumpCm
          ? _value.broadJumpCm
          : broadJumpCm // ignore: cast_nullable_to_non_nullable
              as double?,
      sprint10mS: freezed == sprint10mS
          ? _value.sprint10mS
          : sprint10mS // ignore: cast_nullable_to_non_nullable
              as double?,
      sprint20mS: freezed == sprint20mS
          ? _value.sprint20mS
          : sprint20mS // ignore: cast_nullable_to_non_nullable
              as double?,
      sprint30mS: freezed == sprint30mS
          ? _value.sprint30mS
          : sprint30mS // ignore: cast_nullable_to_non_nullable
              as double?,
      sprint40mS: freezed == sprint40mS
          ? _value.sprint40mS
          : sprint40mS // ignore: cast_nullable_to_non_nullable
              as double?,
      squat1rmKg: freezed == squat1rmKg
          ? _value.squat1rmKg
          : squat1rmKg // ignore: cast_nullable_to_non_nullable
              as double?,
      benchPress1rmKg: freezed == benchPress1rmKg
          ? _value.benchPress1rmKg
          : benchPress1rmKg // ignore: cast_nullable_to_non_nullable
              as double?,
      deadlift1rmKg: freezed == deadlift1rmKg
          ? _value.deadlift1rmKg
          : deadlift1rmKg // ignore: cast_nullable_to_non_nullable
              as double?,
      overheadPress1rmKg: freezed == overheadPress1rmKg
          ? _value.overheadPress1rmKg
          : overheadPress1rmKg // ignore: cast_nullable_to_non_nullable
              as double?,
      pullUp1rmKg: freezed == pullUp1rmKg
          ? _value.pullUp1rmKg
          : pullUp1rmKg // ignore: cast_nullable_to_non_nullable
              as double?,
      vo2maxMlKgMin: freezed == vo2maxMlKgMin
          ? _value.vo2maxMlKgMin
          : vo2maxMlKgMin // ignore: cast_nullable_to_non_nullable
              as double?,
      courseNavetteLevel: freezed == courseNavetteLevel
          ? _value.courseNavetteLevel
          : courseNavetteLevel // ignore: cast_nullable_to_non_nullable
              as double?,
      cooperMeters: freezed == cooperMeters
          ? _value.cooperMeters
          : cooperMeters // ignore: cast_nullable_to_non_nullable
              as double?,
      sitAndReachCm: freezed == sitAndReachCm
          ? _value.sitAndReachCm
          : sitAndReachCm // ignore: cast_nullable_to_non_nullable
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
class _$PerformanceTestImpl implements _PerformanceTest {
  const _$PerformanceTestImpl(
      {required this.id,
      required this.athleteId,
      required this.recordedBy,
      @TimestampConverter() required this.recordedAt,
      this.cmjCm,
      this.squatJumpCm,
      this.abalakovCm,
      this.broadJumpCm,
      this.sprint10mS,
      this.sprint20mS,
      this.sprint30mS,
      this.sprint40mS,
      this.squat1rmKg,
      this.benchPress1rmKg,
      this.deadlift1rmKg,
      this.overheadPress1rmKg,
      this.pullUp1rmKg,
      this.vo2maxMlKgMin,
      this.courseNavetteLevel,
      this.cooperMeters,
      this.sitAndReachCm,
      this.notes});

  factory _$PerformanceTestImpl.fromJson(Map<String, dynamic> json) =>
      _$$PerformanceTestImplFromJson(json);

  @override
  final String id;
  @override
  final String athleteId;

  /// Trainer uid who logged this performance test.
  @override
  final String recordedBy;
  @override
  @TimestampConverter()
  final DateTime recordedAt;
// ─── Saltos (cm) ─────────────────────────────────────────────────────────
  @override
  final double? cmjCm;
  @override
  final double? squatJumpCm;
  @override
  final double? abalakovCm;
  @override
  final double? broadJumpCm;
// ─── Velocidad / sprints (segundos) ──────────────────────────────────────
  @override
  final double? sprint10mS;
  @override
  final double? sprint20mS;
  @override
  final double? sprint30mS;
  @override
  final double? sprint40mS;
// ─── Fuerza máxima 1RM (kg) ──────────────────────────────────────────────
  @override
  final double? squat1rmKg;
  @override
  final double? benchPress1rmKg;
  @override
  final double? deadlift1rmKg;
  @override
  final double? overheadPress1rmKg;
  @override
  final double? pullUp1rmKg;
// ─── Resistencia / otros ─────────────────────────────────────────────────
  @override
  final double? vo2maxMlKgMin;
  @override
  final double? courseNavetteLevel;
  @override
  final double? cooperMeters;
  @override
  final double? sitAndReachCm;
// ─── Meta ─────────────────────────────────────────────────────────────────
  @override
  final String? notes;

  @override
  String toString() {
    return 'PerformanceTest(id: $id, athleteId: $athleteId, recordedBy: $recordedBy, recordedAt: $recordedAt, cmjCm: $cmjCm, squatJumpCm: $squatJumpCm, abalakovCm: $abalakovCm, broadJumpCm: $broadJumpCm, sprint10mS: $sprint10mS, sprint20mS: $sprint20mS, sprint30mS: $sprint30mS, sprint40mS: $sprint40mS, squat1rmKg: $squat1rmKg, benchPress1rmKg: $benchPress1rmKg, deadlift1rmKg: $deadlift1rmKg, overheadPress1rmKg: $overheadPress1rmKg, pullUp1rmKg: $pullUp1rmKg, vo2maxMlKgMin: $vo2maxMlKgMin, courseNavetteLevel: $courseNavetteLevel, cooperMeters: $cooperMeters, sitAndReachCm: $sitAndReachCm, notes: $notes)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PerformanceTestImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.athleteId, athleteId) ||
                other.athleteId == athleteId) &&
            (identical(other.recordedBy, recordedBy) ||
                other.recordedBy == recordedBy) &&
            (identical(other.recordedAt, recordedAt) ||
                other.recordedAt == recordedAt) &&
            (identical(other.cmjCm, cmjCm) || other.cmjCm == cmjCm) &&
            (identical(other.squatJumpCm, squatJumpCm) ||
                other.squatJumpCm == squatJumpCm) &&
            (identical(other.abalakovCm, abalakovCm) ||
                other.abalakovCm == abalakovCm) &&
            (identical(other.broadJumpCm, broadJumpCm) ||
                other.broadJumpCm == broadJumpCm) &&
            (identical(other.sprint10mS, sprint10mS) ||
                other.sprint10mS == sprint10mS) &&
            (identical(other.sprint20mS, sprint20mS) ||
                other.sprint20mS == sprint20mS) &&
            (identical(other.sprint30mS, sprint30mS) ||
                other.sprint30mS == sprint30mS) &&
            (identical(other.sprint40mS, sprint40mS) ||
                other.sprint40mS == sprint40mS) &&
            (identical(other.squat1rmKg, squat1rmKg) ||
                other.squat1rmKg == squat1rmKg) &&
            (identical(other.benchPress1rmKg, benchPress1rmKg) ||
                other.benchPress1rmKg == benchPress1rmKg) &&
            (identical(other.deadlift1rmKg, deadlift1rmKg) ||
                other.deadlift1rmKg == deadlift1rmKg) &&
            (identical(other.overheadPress1rmKg, overheadPress1rmKg) ||
                other.overheadPress1rmKg == overheadPress1rmKg) &&
            (identical(other.pullUp1rmKg, pullUp1rmKg) ||
                other.pullUp1rmKg == pullUp1rmKg) &&
            (identical(other.vo2maxMlKgMin, vo2maxMlKgMin) ||
                other.vo2maxMlKgMin == vo2maxMlKgMin) &&
            (identical(other.courseNavetteLevel, courseNavetteLevel) ||
                other.courseNavetteLevel == courseNavetteLevel) &&
            (identical(other.cooperMeters, cooperMeters) ||
                other.cooperMeters == cooperMeters) &&
            (identical(other.sitAndReachCm, sitAndReachCm) ||
                other.sitAndReachCm == sitAndReachCm) &&
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
        cmjCm,
        squatJumpCm,
        abalakovCm,
        broadJumpCm,
        sprint10mS,
        sprint20mS,
        sprint30mS,
        sprint40mS,
        squat1rmKg,
        benchPress1rmKg,
        deadlift1rmKg,
        overheadPress1rmKg,
        pullUp1rmKg,
        vo2maxMlKgMin,
        courseNavetteLevel,
        cooperMeters,
        sitAndReachCm,
        notes
      ]);

  /// Create a copy of PerformanceTest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PerformanceTestImplCopyWith<_$PerformanceTestImpl> get copyWith =>
      __$$PerformanceTestImplCopyWithImpl<_$PerformanceTestImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PerformanceTestImplToJson(
      this,
    );
  }
}

abstract class _PerformanceTest implements PerformanceTest {
  const factory _PerformanceTest(
      {required final String id,
      required final String athleteId,
      required final String recordedBy,
      @TimestampConverter() required final DateTime recordedAt,
      final double? cmjCm,
      final double? squatJumpCm,
      final double? abalakovCm,
      final double? broadJumpCm,
      final double? sprint10mS,
      final double? sprint20mS,
      final double? sprint30mS,
      final double? sprint40mS,
      final double? squat1rmKg,
      final double? benchPress1rmKg,
      final double? deadlift1rmKg,
      final double? overheadPress1rmKg,
      final double? pullUp1rmKg,
      final double? vo2maxMlKgMin,
      final double? courseNavetteLevel,
      final double? cooperMeters,
      final double? sitAndReachCm,
      final String? notes}) = _$PerformanceTestImpl;

  factory _PerformanceTest.fromJson(Map<String, dynamic> json) =
      _$PerformanceTestImpl.fromJson;

  @override
  String get id;
  @override
  String get athleteId;

  /// Trainer uid who logged this performance test.
  @override
  String get recordedBy;
  @override
  @TimestampConverter()
  DateTime
      get recordedAt; // ─── Saltos (cm) ─────────────────────────────────────────────────────────
  @override
  double? get cmjCm;
  @override
  double? get squatJumpCm;
  @override
  double? get abalakovCm;
  @override
  double?
      get broadJumpCm; // ─── Velocidad / sprints (segundos) ──────────────────────────────────────
  @override
  double? get sprint10mS;
  @override
  double? get sprint20mS;
  @override
  double? get sprint30mS;
  @override
  double?
      get sprint40mS; // ─── Fuerza máxima 1RM (kg) ──────────────────────────────────────────────
  @override
  double? get squat1rmKg;
  @override
  double? get benchPress1rmKg;
  @override
  double? get deadlift1rmKg;
  @override
  double? get overheadPress1rmKg;
  @override
  double?
      get pullUp1rmKg; // ─── Resistencia / otros ─────────────────────────────────────────────────
  @override
  double? get vo2maxMlKgMin;
  @override
  double? get courseNavetteLevel;
  @override
  double? get cooperMeters;
  @override
  double?
      get sitAndReachCm; // ─── Meta ─────────────────────────────────────────────────────────────────
  @override
  String? get notes;

  /// Create a copy of PerformanceTest
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PerformanceTestImplCopyWith<_$PerformanceTestImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
