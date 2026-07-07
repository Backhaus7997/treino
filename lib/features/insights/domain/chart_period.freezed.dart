// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'chart_period.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$ChartPeriodWindow {
  DateTime get currentStart => throw _privateConstructorUsedError;
  DateTime get currentEnd => throw _privateConstructorUsedError;
  DateTime get previousStart => throw _privateConstructorUsedError;
  DateTime get previousEnd => throw _privateConstructorUsedError;

  /// Create a copy of ChartPeriodWindow
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ChartPeriodWindowCopyWith<ChartPeriodWindow> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ChartPeriodWindowCopyWith<$Res> {
  factory $ChartPeriodWindowCopyWith(
          ChartPeriodWindow value, $Res Function(ChartPeriodWindow) then) =
      _$ChartPeriodWindowCopyWithImpl<$Res, ChartPeriodWindow>;
  @useResult
  $Res call(
      {DateTime currentStart,
      DateTime currentEnd,
      DateTime previousStart,
      DateTime previousEnd});
}

/// @nodoc
class _$ChartPeriodWindowCopyWithImpl<$Res, $Val extends ChartPeriodWindow>
    implements $ChartPeriodWindowCopyWith<$Res> {
  _$ChartPeriodWindowCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ChartPeriodWindow
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? currentStart = null,
    Object? currentEnd = null,
    Object? previousStart = null,
    Object? previousEnd = null,
  }) {
    return _then(_value.copyWith(
      currentStart: null == currentStart
          ? _value.currentStart
          : currentStart // ignore: cast_nullable_to_non_nullable
              as DateTime,
      currentEnd: null == currentEnd
          ? _value.currentEnd
          : currentEnd // ignore: cast_nullable_to_non_nullable
              as DateTime,
      previousStart: null == previousStart
          ? _value.previousStart
          : previousStart // ignore: cast_nullable_to_non_nullable
              as DateTime,
      previousEnd: null == previousEnd
          ? _value.previousEnd
          : previousEnd // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ChartPeriodWindowImplCopyWith<$Res>
    implements $ChartPeriodWindowCopyWith<$Res> {
  factory _$$ChartPeriodWindowImplCopyWith(_$ChartPeriodWindowImpl value,
          $Res Function(_$ChartPeriodWindowImpl) then) =
      __$$ChartPeriodWindowImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {DateTime currentStart,
      DateTime currentEnd,
      DateTime previousStart,
      DateTime previousEnd});
}

/// @nodoc
class __$$ChartPeriodWindowImplCopyWithImpl<$Res>
    extends _$ChartPeriodWindowCopyWithImpl<$Res, _$ChartPeriodWindowImpl>
    implements _$$ChartPeriodWindowImplCopyWith<$Res> {
  __$$ChartPeriodWindowImplCopyWithImpl(_$ChartPeriodWindowImpl _value,
      $Res Function(_$ChartPeriodWindowImpl) _then)
      : super(_value, _then);

  /// Create a copy of ChartPeriodWindow
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? currentStart = null,
    Object? currentEnd = null,
    Object? previousStart = null,
    Object? previousEnd = null,
  }) {
    return _then(_$ChartPeriodWindowImpl(
      currentStart: null == currentStart
          ? _value.currentStart
          : currentStart // ignore: cast_nullable_to_non_nullable
              as DateTime,
      currentEnd: null == currentEnd
          ? _value.currentEnd
          : currentEnd // ignore: cast_nullable_to_non_nullable
              as DateTime,
      previousStart: null == previousStart
          ? _value.previousStart
          : previousStart // ignore: cast_nullable_to_non_nullable
              as DateTime,
      previousEnd: null == previousEnd
          ? _value.previousEnd
          : previousEnd // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc

class _$ChartPeriodWindowImpl implements _ChartPeriodWindow {
  const _$ChartPeriodWindowImpl(
      {required this.currentStart,
      required this.currentEnd,
      required this.previousStart,
      required this.previousEnd});

  @override
  final DateTime currentStart;
  @override
  final DateTime currentEnd;
  @override
  final DateTime previousStart;
  @override
  final DateTime previousEnd;

  @override
  String toString() {
    return 'ChartPeriodWindow(currentStart: $currentStart, currentEnd: $currentEnd, previousStart: $previousStart, previousEnd: $previousEnd)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ChartPeriodWindowImpl &&
            (identical(other.currentStart, currentStart) ||
                other.currentStart == currentStart) &&
            (identical(other.currentEnd, currentEnd) ||
                other.currentEnd == currentEnd) &&
            (identical(other.previousStart, previousStart) ||
                other.previousStart == previousStart) &&
            (identical(other.previousEnd, previousEnd) ||
                other.previousEnd == previousEnd));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType, currentStart, currentEnd, previousStart, previousEnd);

  /// Create a copy of ChartPeriodWindow
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ChartPeriodWindowImplCopyWith<_$ChartPeriodWindowImpl> get copyWith =>
      __$$ChartPeriodWindowImplCopyWithImpl<_$ChartPeriodWindowImpl>(
          this, _$identity);
}

abstract class _ChartPeriodWindow implements ChartPeriodWindow {
  const factory _ChartPeriodWindow(
      {required final DateTime currentStart,
      required final DateTime currentEnd,
      required final DateTime previousStart,
      required final DateTime previousEnd}) = _$ChartPeriodWindowImpl;

  @override
  DateTime get currentStart;
  @override
  DateTime get currentEnd;
  @override
  DateTime get previousStart;
  @override
  DateTime get previousEnd;

  /// Create a copy of ChartPeriodWindow
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ChartPeriodWindowImplCopyWith<_$ChartPeriodWindowImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
