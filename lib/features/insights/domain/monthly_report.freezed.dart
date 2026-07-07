// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'monthly_report.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$MonthlyReportPoint {
  DateTime get month => throw _privateConstructorUsedError;
  int get workoutsCount => throw _privateConstructorUsedError;
  int get durationMin => throw _privateConstructorUsedError;
  double get volumeKg => throw _privateConstructorUsedError;
  int get setsCount => throw _privateConstructorUsedError;

  /// Create a copy of MonthlyReportPoint
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $MonthlyReportPointCopyWith<MonthlyReportPoint> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MonthlyReportPointCopyWith<$Res> {
  factory $MonthlyReportPointCopyWith(
          MonthlyReportPoint value, $Res Function(MonthlyReportPoint) then) =
      _$MonthlyReportPointCopyWithImpl<$Res, MonthlyReportPoint>;
  @useResult
  $Res call(
      {DateTime month,
      int workoutsCount,
      int durationMin,
      double volumeKg,
      int setsCount});
}

/// @nodoc
class _$MonthlyReportPointCopyWithImpl<$Res, $Val extends MonthlyReportPoint>
    implements $MonthlyReportPointCopyWith<$Res> {
  _$MonthlyReportPointCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of MonthlyReportPoint
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? month = null,
    Object? workoutsCount = null,
    Object? durationMin = null,
    Object? volumeKg = null,
    Object? setsCount = null,
  }) {
    return _then(_value.copyWith(
      month: null == month
          ? _value.month
          : month // ignore: cast_nullable_to_non_nullable
              as DateTime,
      workoutsCount: null == workoutsCount
          ? _value.workoutsCount
          : workoutsCount // ignore: cast_nullable_to_non_nullable
              as int,
      durationMin: null == durationMin
          ? _value.durationMin
          : durationMin // ignore: cast_nullable_to_non_nullable
              as int,
      volumeKg: null == volumeKg
          ? _value.volumeKg
          : volumeKg // ignore: cast_nullable_to_non_nullable
              as double,
      setsCount: null == setsCount
          ? _value.setsCount
          : setsCount // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$MonthlyReportPointImplCopyWith<$Res>
    implements $MonthlyReportPointCopyWith<$Res> {
  factory _$$MonthlyReportPointImplCopyWith(_$MonthlyReportPointImpl value,
          $Res Function(_$MonthlyReportPointImpl) then) =
      __$$MonthlyReportPointImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {DateTime month,
      int workoutsCount,
      int durationMin,
      double volumeKg,
      int setsCount});
}

/// @nodoc
class __$$MonthlyReportPointImplCopyWithImpl<$Res>
    extends _$MonthlyReportPointCopyWithImpl<$Res, _$MonthlyReportPointImpl>
    implements _$$MonthlyReportPointImplCopyWith<$Res> {
  __$$MonthlyReportPointImplCopyWithImpl(_$MonthlyReportPointImpl _value,
      $Res Function(_$MonthlyReportPointImpl) _then)
      : super(_value, _then);

  /// Create a copy of MonthlyReportPoint
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? month = null,
    Object? workoutsCount = null,
    Object? durationMin = null,
    Object? volumeKg = null,
    Object? setsCount = null,
  }) {
    return _then(_$MonthlyReportPointImpl(
      month: null == month
          ? _value.month
          : month // ignore: cast_nullable_to_non_nullable
              as DateTime,
      workoutsCount: null == workoutsCount
          ? _value.workoutsCount
          : workoutsCount // ignore: cast_nullable_to_non_nullable
              as int,
      durationMin: null == durationMin
          ? _value.durationMin
          : durationMin // ignore: cast_nullable_to_non_nullable
              as int,
      volumeKg: null == volumeKg
          ? _value.volumeKg
          : volumeKg // ignore: cast_nullable_to_non_nullable
              as double,
      setsCount: null == setsCount
          ? _value.setsCount
          : setsCount // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc

class _$MonthlyReportPointImpl implements _MonthlyReportPoint {
  const _$MonthlyReportPointImpl(
      {required this.month,
      required this.workoutsCount,
      required this.durationMin,
      required this.volumeKg,
      required this.setsCount});

  @override
  final DateTime month;
  @override
  final int workoutsCount;
  @override
  final int durationMin;
  @override
  final double volumeKg;
  @override
  final int setsCount;

  @override
  String toString() {
    return 'MonthlyReportPoint(month: $month, workoutsCount: $workoutsCount, durationMin: $durationMin, volumeKg: $volumeKg, setsCount: $setsCount)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MonthlyReportPointImpl &&
            (identical(other.month, month) || other.month == month) &&
            (identical(other.workoutsCount, workoutsCount) ||
                other.workoutsCount == workoutsCount) &&
            (identical(other.durationMin, durationMin) ||
                other.durationMin == durationMin) &&
            (identical(other.volumeKg, volumeKg) ||
                other.volumeKg == volumeKg) &&
            (identical(other.setsCount, setsCount) ||
                other.setsCount == setsCount));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType, month, workoutsCount, durationMin, volumeKg, setsCount);

  /// Create a copy of MonthlyReportPoint
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MonthlyReportPointImplCopyWith<_$MonthlyReportPointImpl> get copyWith =>
      __$$MonthlyReportPointImplCopyWithImpl<_$MonthlyReportPointImpl>(
          this, _$identity);
}

abstract class _MonthlyReportPoint implements MonthlyReportPoint {
  const factory _MonthlyReportPoint(
      {required final DateTime month,
      required final int workoutsCount,
      required final int durationMin,
      required final double volumeKg,
      required final int setsCount}) = _$MonthlyReportPointImpl;

  @override
  DateTime get month;
  @override
  int get workoutsCount;
  @override
  int get durationMin;
  @override
  double get volumeKg;
  @override
  int get setsCount;

  /// Create a copy of MonthlyReportPoint
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MonthlyReportPointImplCopyWith<_$MonthlyReportPointImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$MonthlyReport {
  List<MonthlyReportPoint> get points => throw _privateConstructorUsedError;

  /// Create a copy of MonthlyReport
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $MonthlyReportCopyWith<MonthlyReport> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MonthlyReportCopyWith<$Res> {
  factory $MonthlyReportCopyWith(
          MonthlyReport value, $Res Function(MonthlyReport) then) =
      _$MonthlyReportCopyWithImpl<$Res, MonthlyReport>;
  @useResult
  $Res call({List<MonthlyReportPoint> points});
}

/// @nodoc
class _$MonthlyReportCopyWithImpl<$Res, $Val extends MonthlyReport>
    implements $MonthlyReportCopyWith<$Res> {
  _$MonthlyReportCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of MonthlyReport
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? points = null,
  }) {
    return _then(_value.copyWith(
      points: null == points
          ? _value.points
          : points // ignore: cast_nullable_to_non_nullable
              as List<MonthlyReportPoint>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$MonthlyReportImplCopyWith<$Res>
    implements $MonthlyReportCopyWith<$Res> {
  factory _$$MonthlyReportImplCopyWith(
          _$MonthlyReportImpl value, $Res Function(_$MonthlyReportImpl) then) =
      __$$MonthlyReportImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({List<MonthlyReportPoint> points});
}

/// @nodoc
class __$$MonthlyReportImplCopyWithImpl<$Res>
    extends _$MonthlyReportCopyWithImpl<$Res, _$MonthlyReportImpl>
    implements _$$MonthlyReportImplCopyWith<$Res> {
  __$$MonthlyReportImplCopyWithImpl(
      _$MonthlyReportImpl _value, $Res Function(_$MonthlyReportImpl) _then)
      : super(_value, _then);

  /// Create a copy of MonthlyReport
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? points = null,
  }) {
    return _then(_$MonthlyReportImpl(
      points: null == points
          ? _value._points
          : points // ignore: cast_nullable_to_non_nullable
              as List<MonthlyReportPoint>,
    ));
  }
}

/// @nodoc

class _$MonthlyReportImpl implements _MonthlyReport {
  const _$MonthlyReportImpl({required final List<MonthlyReportPoint> points})
      : _points = points;

  final List<MonthlyReportPoint> _points;
  @override
  List<MonthlyReportPoint> get points {
    if (_points is EqualUnmodifiableListView) return _points;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_points);
  }

  @override
  String toString() {
    return 'MonthlyReport(points: $points)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MonthlyReportImpl &&
            const DeepCollectionEquality().equals(other._points, _points));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, const DeepCollectionEquality().hash(_points));

  /// Create a copy of MonthlyReport
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MonthlyReportImplCopyWith<_$MonthlyReportImpl> get copyWith =>
      __$$MonthlyReportImplCopyWithImpl<_$MonthlyReportImpl>(this, _$identity);
}

abstract class _MonthlyReport implements MonthlyReport {
  const factory _MonthlyReport(
      {required final List<MonthlyReportPoint> points}) = _$MonthlyReportImpl;

  @override
  List<MonthlyReportPoint> get points;

  /// Create a copy of MonthlyReport
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MonthlyReportImplCopyWith<_$MonthlyReportImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
