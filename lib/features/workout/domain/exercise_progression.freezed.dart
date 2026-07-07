// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'exercise_progression.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$ProgressionPoint {
  DateTime get date => throw _privateConstructorUsedError;
  double get value => throw _privateConstructorUsedError;

  /// Create a copy of ProgressionPoint
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ProgressionPointCopyWith<ProgressionPoint> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ProgressionPointCopyWith<$Res> {
  factory $ProgressionPointCopyWith(
          ProgressionPoint value, $Res Function(ProgressionPoint) then) =
      _$ProgressionPointCopyWithImpl<$Res, ProgressionPoint>;
  @useResult
  $Res call({DateTime date, double value});
}

/// @nodoc
class _$ProgressionPointCopyWithImpl<$Res, $Val extends ProgressionPoint>
    implements $ProgressionPointCopyWith<$Res> {
  _$ProgressionPointCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ProgressionPoint
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? date = null,
    Object? value = null,
  }) {
    return _then(_value.copyWith(
      date: null == date
          ? _value.date
          : date // ignore: cast_nullable_to_non_nullable
              as DateTime,
      value: null == value
          ? _value.value
          : value // ignore: cast_nullable_to_non_nullable
              as double,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ProgressionPointImplCopyWith<$Res>
    implements $ProgressionPointCopyWith<$Res> {
  factory _$$ProgressionPointImplCopyWith(_$ProgressionPointImpl value,
          $Res Function(_$ProgressionPointImpl) then) =
      __$$ProgressionPointImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({DateTime date, double value});
}

/// @nodoc
class __$$ProgressionPointImplCopyWithImpl<$Res>
    extends _$ProgressionPointCopyWithImpl<$Res, _$ProgressionPointImpl>
    implements _$$ProgressionPointImplCopyWith<$Res> {
  __$$ProgressionPointImplCopyWithImpl(_$ProgressionPointImpl _value,
      $Res Function(_$ProgressionPointImpl) _then)
      : super(_value, _then);

  /// Create a copy of ProgressionPoint
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? date = null,
    Object? value = null,
  }) {
    return _then(_$ProgressionPointImpl(
      date: null == date
          ? _value.date
          : date // ignore: cast_nullable_to_non_nullable
              as DateTime,
      value: null == value
          ? _value.value
          : value // ignore: cast_nullable_to_non_nullable
              as double,
    ));
  }
}

/// @nodoc

class _$ProgressionPointImpl implements _ProgressionPoint {
  const _$ProgressionPointImpl({required this.date, required this.value});

  @override
  final DateTime date;
  @override
  final double value;

  @override
  String toString() {
    return 'ProgressionPoint(date: $date, value: $value)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ProgressionPointImpl &&
            (identical(other.date, date) || other.date == date) &&
            (identical(other.value, value) || other.value == value));
  }

  @override
  int get hashCode => Object.hash(runtimeType, date, value);

  /// Create a copy of ProgressionPoint
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ProgressionPointImplCopyWith<_$ProgressionPointImpl> get copyWith =>
      __$$ProgressionPointImplCopyWithImpl<_$ProgressionPointImpl>(
          this, _$identity);
}

abstract class _ProgressionPoint implements ProgressionPoint {
  const factory _ProgressionPoint(
      {required final DateTime date,
      required final double value}) = _$ProgressionPointImpl;

  @override
  DateTime get date;
  @override
  double get value;

  /// Create a copy of ProgressionPoint
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ProgressionPointImplCopyWith<_$ProgressionPointImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$PersonalRecord {
  ProgressionRecordType get recordType => throw _privateConstructorUsedError;
  double get value => throw _privateConstructorUsedError;
  DateTime get achievedAt => throw _privateConstructorUsedError;

  /// Create a copy of PersonalRecord
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PersonalRecordCopyWith<PersonalRecord> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PersonalRecordCopyWith<$Res> {
  factory $PersonalRecordCopyWith(
          PersonalRecord value, $Res Function(PersonalRecord) then) =
      _$PersonalRecordCopyWithImpl<$Res, PersonalRecord>;
  @useResult
  $Res call(
      {ProgressionRecordType recordType, double value, DateTime achievedAt});
}

/// @nodoc
class _$PersonalRecordCopyWithImpl<$Res, $Val extends PersonalRecord>
    implements $PersonalRecordCopyWith<$Res> {
  _$PersonalRecordCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PersonalRecord
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? recordType = null,
    Object? value = null,
    Object? achievedAt = null,
  }) {
    return _then(_value.copyWith(
      recordType: null == recordType
          ? _value.recordType
          : recordType // ignore: cast_nullable_to_non_nullable
              as ProgressionRecordType,
      value: null == value
          ? _value.value
          : value // ignore: cast_nullable_to_non_nullable
              as double,
      achievedAt: null == achievedAt
          ? _value.achievedAt
          : achievedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PersonalRecordImplCopyWith<$Res>
    implements $PersonalRecordCopyWith<$Res> {
  factory _$$PersonalRecordImplCopyWith(_$PersonalRecordImpl value,
          $Res Function(_$PersonalRecordImpl) then) =
      __$$PersonalRecordImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {ProgressionRecordType recordType, double value, DateTime achievedAt});
}

/// @nodoc
class __$$PersonalRecordImplCopyWithImpl<$Res>
    extends _$PersonalRecordCopyWithImpl<$Res, _$PersonalRecordImpl>
    implements _$$PersonalRecordImplCopyWith<$Res> {
  __$$PersonalRecordImplCopyWithImpl(
      _$PersonalRecordImpl _value, $Res Function(_$PersonalRecordImpl) _then)
      : super(_value, _then);

  /// Create a copy of PersonalRecord
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? recordType = null,
    Object? value = null,
    Object? achievedAt = null,
  }) {
    return _then(_$PersonalRecordImpl(
      recordType: null == recordType
          ? _value.recordType
          : recordType // ignore: cast_nullable_to_non_nullable
              as ProgressionRecordType,
      value: null == value
          ? _value.value
          : value // ignore: cast_nullable_to_non_nullable
              as double,
      achievedAt: null == achievedAt
          ? _value.achievedAt
          : achievedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc

class _$PersonalRecordImpl implements _PersonalRecord {
  const _$PersonalRecordImpl(
      {required this.recordType,
      required this.value,
      required this.achievedAt});

  @override
  final ProgressionRecordType recordType;
  @override
  final double value;
  @override
  final DateTime achievedAt;

  @override
  String toString() {
    return 'PersonalRecord(recordType: $recordType, value: $value, achievedAt: $achievedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PersonalRecordImpl &&
            (identical(other.recordType, recordType) ||
                other.recordType == recordType) &&
            (identical(other.value, value) || other.value == value) &&
            (identical(other.achievedAt, achievedAt) ||
                other.achievedAt == achievedAt));
  }

  @override
  int get hashCode => Object.hash(runtimeType, recordType, value, achievedAt);

  /// Create a copy of PersonalRecord
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PersonalRecordImplCopyWith<_$PersonalRecordImpl> get copyWith =>
      __$$PersonalRecordImplCopyWithImpl<_$PersonalRecordImpl>(
          this, _$identity);
}

abstract class _PersonalRecord implements PersonalRecord {
  const factory _PersonalRecord(
      {required final ProgressionRecordType recordType,
      required final double value,
      required final DateTime achievedAt}) = _$PersonalRecordImpl;

  @override
  ProgressionRecordType get recordType;
  @override
  double get value;
  @override
  DateTime get achievedAt;

  /// Create a copy of PersonalRecord
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PersonalRecordImplCopyWith<_$PersonalRecordImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$ExerciseProgression {
  String get exerciseId => throw _privateConstructorUsedError;
  String get exerciseName => throw _privateConstructorUsedError;
  List<ProgressionPoint> get heaviestWeightSeries =>
      throw _privateConstructorUsedError;
  List<ProgressionPoint> get oneRepMaxSeries =>
      throw _privateConstructorUsedError;
  List<ProgressionPoint> get bestSetVolumeSeries =>
      throw _privateConstructorUsedError;
  List<ProgressionPoint> get bestSessionVolumeSeries =>
      throw _privateConstructorUsedError;
  List<PersonalRecord> get personalRecords =>
      throw _privateConstructorUsedError;
  int get frequencyLast8Weeks => throw _privateConstructorUsedError;

  /// Create a copy of ExerciseProgression
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ExerciseProgressionCopyWith<ExerciseProgression> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ExerciseProgressionCopyWith<$Res> {
  factory $ExerciseProgressionCopyWith(
          ExerciseProgression value, $Res Function(ExerciseProgression) then) =
      _$ExerciseProgressionCopyWithImpl<$Res, ExerciseProgression>;
  @useResult
  $Res call(
      {String exerciseId,
      String exerciseName,
      List<ProgressionPoint> heaviestWeightSeries,
      List<ProgressionPoint> oneRepMaxSeries,
      List<ProgressionPoint> bestSetVolumeSeries,
      List<ProgressionPoint> bestSessionVolumeSeries,
      List<PersonalRecord> personalRecords,
      int frequencyLast8Weeks});
}

/// @nodoc
class _$ExerciseProgressionCopyWithImpl<$Res, $Val extends ExerciseProgression>
    implements $ExerciseProgressionCopyWith<$Res> {
  _$ExerciseProgressionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ExerciseProgression
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? exerciseId = null,
    Object? exerciseName = null,
    Object? heaviestWeightSeries = null,
    Object? oneRepMaxSeries = null,
    Object? bestSetVolumeSeries = null,
    Object? bestSessionVolumeSeries = null,
    Object? personalRecords = null,
    Object? frequencyLast8Weeks = null,
  }) {
    return _then(_value.copyWith(
      exerciseId: null == exerciseId
          ? _value.exerciseId
          : exerciseId // ignore: cast_nullable_to_non_nullable
              as String,
      exerciseName: null == exerciseName
          ? _value.exerciseName
          : exerciseName // ignore: cast_nullable_to_non_nullable
              as String,
      heaviestWeightSeries: null == heaviestWeightSeries
          ? _value.heaviestWeightSeries
          : heaviestWeightSeries // ignore: cast_nullable_to_non_nullable
              as List<ProgressionPoint>,
      oneRepMaxSeries: null == oneRepMaxSeries
          ? _value.oneRepMaxSeries
          : oneRepMaxSeries // ignore: cast_nullable_to_non_nullable
              as List<ProgressionPoint>,
      bestSetVolumeSeries: null == bestSetVolumeSeries
          ? _value.bestSetVolumeSeries
          : bestSetVolumeSeries // ignore: cast_nullable_to_non_nullable
              as List<ProgressionPoint>,
      bestSessionVolumeSeries: null == bestSessionVolumeSeries
          ? _value.bestSessionVolumeSeries
          : bestSessionVolumeSeries // ignore: cast_nullable_to_non_nullable
              as List<ProgressionPoint>,
      personalRecords: null == personalRecords
          ? _value.personalRecords
          : personalRecords // ignore: cast_nullable_to_non_nullable
              as List<PersonalRecord>,
      frequencyLast8Weeks: null == frequencyLast8Weeks
          ? _value.frequencyLast8Weeks
          : frequencyLast8Weeks // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ExerciseProgressionImplCopyWith<$Res>
    implements $ExerciseProgressionCopyWith<$Res> {
  factory _$$ExerciseProgressionImplCopyWith(_$ExerciseProgressionImpl value,
          $Res Function(_$ExerciseProgressionImpl) then) =
      __$$ExerciseProgressionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String exerciseId,
      String exerciseName,
      List<ProgressionPoint> heaviestWeightSeries,
      List<ProgressionPoint> oneRepMaxSeries,
      List<ProgressionPoint> bestSetVolumeSeries,
      List<ProgressionPoint> bestSessionVolumeSeries,
      List<PersonalRecord> personalRecords,
      int frequencyLast8Weeks});
}

/// @nodoc
class __$$ExerciseProgressionImplCopyWithImpl<$Res>
    extends _$ExerciseProgressionCopyWithImpl<$Res, _$ExerciseProgressionImpl>
    implements _$$ExerciseProgressionImplCopyWith<$Res> {
  __$$ExerciseProgressionImplCopyWithImpl(_$ExerciseProgressionImpl _value,
      $Res Function(_$ExerciseProgressionImpl) _then)
      : super(_value, _then);

  /// Create a copy of ExerciseProgression
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? exerciseId = null,
    Object? exerciseName = null,
    Object? heaviestWeightSeries = null,
    Object? oneRepMaxSeries = null,
    Object? bestSetVolumeSeries = null,
    Object? bestSessionVolumeSeries = null,
    Object? personalRecords = null,
    Object? frequencyLast8Weeks = null,
  }) {
    return _then(_$ExerciseProgressionImpl(
      exerciseId: null == exerciseId
          ? _value.exerciseId
          : exerciseId // ignore: cast_nullable_to_non_nullable
              as String,
      exerciseName: null == exerciseName
          ? _value.exerciseName
          : exerciseName // ignore: cast_nullable_to_non_nullable
              as String,
      heaviestWeightSeries: null == heaviestWeightSeries
          ? _value._heaviestWeightSeries
          : heaviestWeightSeries // ignore: cast_nullable_to_non_nullable
              as List<ProgressionPoint>,
      oneRepMaxSeries: null == oneRepMaxSeries
          ? _value._oneRepMaxSeries
          : oneRepMaxSeries // ignore: cast_nullable_to_non_nullable
              as List<ProgressionPoint>,
      bestSetVolumeSeries: null == bestSetVolumeSeries
          ? _value._bestSetVolumeSeries
          : bestSetVolumeSeries // ignore: cast_nullable_to_non_nullable
              as List<ProgressionPoint>,
      bestSessionVolumeSeries: null == bestSessionVolumeSeries
          ? _value._bestSessionVolumeSeries
          : bestSessionVolumeSeries // ignore: cast_nullable_to_non_nullable
              as List<ProgressionPoint>,
      personalRecords: null == personalRecords
          ? _value._personalRecords
          : personalRecords // ignore: cast_nullable_to_non_nullable
              as List<PersonalRecord>,
      frequencyLast8Weeks: null == frequencyLast8Weeks
          ? _value.frequencyLast8Weeks
          : frequencyLast8Weeks // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc

class _$ExerciseProgressionImpl implements _ExerciseProgression {
  const _$ExerciseProgressionImpl(
      {required this.exerciseId,
      required this.exerciseName,
      required final List<ProgressionPoint> heaviestWeightSeries,
      required final List<ProgressionPoint> oneRepMaxSeries,
      required final List<ProgressionPoint> bestSetVolumeSeries,
      required final List<ProgressionPoint> bestSessionVolumeSeries,
      required final List<PersonalRecord> personalRecords,
      required this.frequencyLast8Weeks})
      : _heaviestWeightSeries = heaviestWeightSeries,
        _oneRepMaxSeries = oneRepMaxSeries,
        _bestSetVolumeSeries = bestSetVolumeSeries,
        _bestSessionVolumeSeries = bestSessionVolumeSeries,
        _personalRecords = personalRecords;

  @override
  final String exerciseId;
  @override
  final String exerciseName;
  final List<ProgressionPoint> _heaviestWeightSeries;
  @override
  List<ProgressionPoint> get heaviestWeightSeries {
    if (_heaviestWeightSeries is EqualUnmodifiableListView)
      return _heaviestWeightSeries;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_heaviestWeightSeries);
  }

  final List<ProgressionPoint> _oneRepMaxSeries;
  @override
  List<ProgressionPoint> get oneRepMaxSeries {
    if (_oneRepMaxSeries is EqualUnmodifiableListView) return _oneRepMaxSeries;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_oneRepMaxSeries);
  }

  final List<ProgressionPoint> _bestSetVolumeSeries;
  @override
  List<ProgressionPoint> get bestSetVolumeSeries {
    if (_bestSetVolumeSeries is EqualUnmodifiableListView)
      return _bestSetVolumeSeries;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_bestSetVolumeSeries);
  }

  final List<ProgressionPoint> _bestSessionVolumeSeries;
  @override
  List<ProgressionPoint> get bestSessionVolumeSeries {
    if (_bestSessionVolumeSeries is EqualUnmodifiableListView)
      return _bestSessionVolumeSeries;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_bestSessionVolumeSeries);
  }

  final List<PersonalRecord> _personalRecords;
  @override
  List<PersonalRecord> get personalRecords {
    if (_personalRecords is EqualUnmodifiableListView) return _personalRecords;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_personalRecords);
  }

  @override
  final int frequencyLast8Weeks;

  @override
  String toString() {
    return 'ExerciseProgression(exerciseId: $exerciseId, exerciseName: $exerciseName, heaviestWeightSeries: $heaviestWeightSeries, oneRepMaxSeries: $oneRepMaxSeries, bestSetVolumeSeries: $bestSetVolumeSeries, bestSessionVolumeSeries: $bestSessionVolumeSeries, personalRecords: $personalRecords, frequencyLast8Weeks: $frequencyLast8Weeks)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ExerciseProgressionImpl &&
            (identical(other.exerciseId, exerciseId) ||
                other.exerciseId == exerciseId) &&
            (identical(other.exerciseName, exerciseName) ||
                other.exerciseName == exerciseName) &&
            const DeepCollectionEquality()
                .equals(other._heaviestWeightSeries, _heaviestWeightSeries) &&
            const DeepCollectionEquality()
                .equals(other._oneRepMaxSeries, _oneRepMaxSeries) &&
            const DeepCollectionEquality()
                .equals(other._bestSetVolumeSeries, _bestSetVolumeSeries) &&
            const DeepCollectionEquality().equals(
                other._bestSessionVolumeSeries, _bestSessionVolumeSeries) &&
            const DeepCollectionEquality()
                .equals(other._personalRecords, _personalRecords) &&
            (identical(other.frequencyLast8Weeks, frequencyLast8Weeks) ||
                other.frequencyLast8Weeks == frequencyLast8Weeks));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      exerciseId,
      exerciseName,
      const DeepCollectionEquality().hash(_heaviestWeightSeries),
      const DeepCollectionEquality().hash(_oneRepMaxSeries),
      const DeepCollectionEquality().hash(_bestSetVolumeSeries),
      const DeepCollectionEquality().hash(_bestSessionVolumeSeries),
      const DeepCollectionEquality().hash(_personalRecords),
      frequencyLast8Weeks);

  /// Create a copy of ExerciseProgression
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ExerciseProgressionImplCopyWith<_$ExerciseProgressionImpl> get copyWith =>
      __$$ExerciseProgressionImplCopyWithImpl<_$ExerciseProgressionImpl>(
          this, _$identity);
}

abstract class _ExerciseProgression implements ExerciseProgression {
  const factory _ExerciseProgression(
      {required final String exerciseId,
      required final String exerciseName,
      required final List<ProgressionPoint> heaviestWeightSeries,
      required final List<ProgressionPoint> oneRepMaxSeries,
      required final List<ProgressionPoint> bestSetVolumeSeries,
      required final List<ProgressionPoint> bestSessionVolumeSeries,
      required final List<PersonalRecord> personalRecords,
      required final int frequencyLast8Weeks}) = _$ExerciseProgressionImpl;

  @override
  String get exerciseId;
  @override
  String get exerciseName;
  @override
  List<ProgressionPoint> get heaviestWeightSeries;
  @override
  List<ProgressionPoint> get oneRepMaxSeries;
  @override
  List<ProgressionPoint> get bestSetVolumeSeries;
  @override
  List<ProgressionPoint> get bestSessionVolumeSeries;
  @override
  List<PersonalRecord> get personalRecords;
  @override
  int get frequencyLast8Weeks;

  /// Create a copy of ExerciseProgression
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ExerciseProgressionImplCopyWith<_$ExerciseProgressionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$ExerciseListEntry {
  String get exerciseId => throw _privateConstructorUsedError;
  String get exerciseName => throw _privateConstructorUsedError;

  /// Create a copy of ExerciseListEntry
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ExerciseListEntryCopyWith<ExerciseListEntry> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ExerciseListEntryCopyWith<$Res> {
  factory $ExerciseListEntryCopyWith(
          ExerciseListEntry value, $Res Function(ExerciseListEntry) then) =
      _$ExerciseListEntryCopyWithImpl<$Res, ExerciseListEntry>;
  @useResult
  $Res call({String exerciseId, String exerciseName});
}

/// @nodoc
class _$ExerciseListEntryCopyWithImpl<$Res, $Val extends ExerciseListEntry>
    implements $ExerciseListEntryCopyWith<$Res> {
  _$ExerciseListEntryCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ExerciseListEntry
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? exerciseId = null,
    Object? exerciseName = null,
  }) {
    return _then(_value.copyWith(
      exerciseId: null == exerciseId
          ? _value.exerciseId
          : exerciseId // ignore: cast_nullable_to_non_nullable
              as String,
      exerciseName: null == exerciseName
          ? _value.exerciseName
          : exerciseName // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ExerciseListEntryImplCopyWith<$Res>
    implements $ExerciseListEntryCopyWith<$Res> {
  factory _$$ExerciseListEntryImplCopyWith(_$ExerciseListEntryImpl value,
          $Res Function(_$ExerciseListEntryImpl) then) =
      __$$ExerciseListEntryImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String exerciseId, String exerciseName});
}

/// @nodoc
class __$$ExerciseListEntryImplCopyWithImpl<$Res>
    extends _$ExerciseListEntryCopyWithImpl<$Res, _$ExerciseListEntryImpl>
    implements _$$ExerciseListEntryImplCopyWith<$Res> {
  __$$ExerciseListEntryImplCopyWithImpl(_$ExerciseListEntryImpl _value,
      $Res Function(_$ExerciseListEntryImpl) _then)
      : super(_value, _then);

  /// Create a copy of ExerciseListEntry
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? exerciseId = null,
    Object? exerciseName = null,
  }) {
    return _then(_$ExerciseListEntryImpl(
      exerciseId: null == exerciseId
          ? _value.exerciseId
          : exerciseId // ignore: cast_nullable_to_non_nullable
              as String,
      exerciseName: null == exerciseName
          ? _value.exerciseName
          : exerciseName // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$ExerciseListEntryImpl implements _ExerciseListEntry {
  const _$ExerciseListEntryImpl(
      {required this.exerciseId, required this.exerciseName});

  @override
  final String exerciseId;
  @override
  final String exerciseName;

  @override
  String toString() {
    return 'ExerciseListEntry(exerciseId: $exerciseId, exerciseName: $exerciseName)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ExerciseListEntryImpl &&
            (identical(other.exerciseId, exerciseId) ||
                other.exerciseId == exerciseId) &&
            (identical(other.exerciseName, exerciseName) ||
                other.exerciseName == exerciseName));
  }

  @override
  int get hashCode => Object.hash(runtimeType, exerciseId, exerciseName);

  /// Create a copy of ExerciseListEntry
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ExerciseListEntryImplCopyWith<_$ExerciseListEntryImpl> get copyWith =>
      __$$ExerciseListEntryImplCopyWithImpl<_$ExerciseListEntryImpl>(
          this, _$identity);
}

abstract class _ExerciseListEntry implements ExerciseListEntry {
  const factory _ExerciseListEntry(
      {required final String exerciseId,
      required final String exerciseName}) = _$ExerciseListEntryImpl;

  @override
  String get exerciseId;
  @override
  String get exerciseName;

  /// Create a copy of ExerciseListEntry
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ExerciseListEntryImplCopyWith<_$ExerciseListEntryImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
