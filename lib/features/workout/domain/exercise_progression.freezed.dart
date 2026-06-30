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
mixin _$ExerciseProgression {
  String get exerciseId => throw _privateConstructorUsedError;
  String get exerciseName => throw _privateConstructorUsedError;
  List<ProgressionPoint> get prSeries => throw _privateConstructorUsedError;
  List<ProgressionPoint> get volumeSeries => throw _privateConstructorUsedError;
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
      List<ProgressionPoint> prSeries,
      List<ProgressionPoint> volumeSeries,
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
    Object? prSeries = null,
    Object? volumeSeries = null,
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
      prSeries: null == prSeries
          ? _value.prSeries
          : prSeries // ignore: cast_nullable_to_non_nullable
              as List<ProgressionPoint>,
      volumeSeries: null == volumeSeries
          ? _value.volumeSeries
          : volumeSeries // ignore: cast_nullable_to_non_nullable
              as List<ProgressionPoint>,
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
      List<ProgressionPoint> prSeries,
      List<ProgressionPoint> volumeSeries,
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
    Object? prSeries = null,
    Object? volumeSeries = null,
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
      prSeries: null == prSeries
          ? _value._prSeries
          : prSeries // ignore: cast_nullable_to_non_nullable
              as List<ProgressionPoint>,
      volumeSeries: null == volumeSeries
          ? _value._volumeSeries
          : volumeSeries // ignore: cast_nullable_to_non_nullable
              as List<ProgressionPoint>,
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
      required final List<ProgressionPoint> prSeries,
      required final List<ProgressionPoint> volumeSeries,
      required this.frequencyLast8Weeks})
      : _prSeries = prSeries,
        _volumeSeries = volumeSeries;

  @override
  final String exerciseId;
  @override
  final String exerciseName;
  final List<ProgressionPoint> _prSeries;
  @override
  List<ProgressionPoint> get prSeries {
    if (_prSeries is EqualUnmodifiableListView) return _prSeries;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_prSeries);
  }

  final List<ProgressionPoint> _volumeSeries;
  @override
  List<ProgressionPoint> get volumeSeries {
    if (_volumeSeries is EqualUnmodifiableListView) return _volumeSeries;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_volumeSeries);
  }

  @override
  final int frequencyLast8Weeks;

  @override
  String toString() {
    return 'ExerciseProgression(exerciseId: $exerciseId, exerciseName: $exerciseName, prSeries: $prSeries, volumeSeries: $volumeSeries, frequencyLast8Weeks: $frequencyLast8Weeks)';
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
            const DeepCollectionEquality().equals(other._prSeries, _prSeries) &&
            const DeepCollectionEquality()
                .equals(other._volumeSeries, _volumeSeries) &&
            (identical(other.frequencyLast8Weeks, frequencyLast8Weeks) ||
                other.frequencyLast8Weeks == frequencyLast8Weeks));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      exerciseId,
      exerciseName,
      const DeepCollectionEquality().hash(_prSeries),
      const DeepCollectionEquality().hash(_volumeSeries),
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
      required final List<ProgressionPoint> prSeries,
      required final List<ProgressionPoint> volumeSeries,
      required final int frequencyLast8Weeks}) = _$ExerciseProgressionImpl;

  @override
  String get exerciseId;
  @override
  String get exerciseName;
  @override
  List<ProgressionPoint> get prSeries;
  @override
  List<ProgressionPoint> get volumeSeries;
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
