// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'workout_days_month.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$WorkoutDaysMonth {
  DateTime get month => throw _privateConstructorUsedError;
  Set<DateTime> get trainedDays => throw _privateConstructorUsedError;
  int get streak => throw _privateConstructorUsedError;

  /// Create a copy of WorkoutDaysMonth
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $WorkoutDaysMonthCopyWith<WorkoutDaysMonth> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $WorkoutDaysMonthCopyWith<$Res> {
  factory $WorkoutDaysMonthCopyWith(
          WorkoutDaysMonth value, $Res Function(WorkoutDaysMonth) then) =
      _$WorkoutDaysMonthCopyWithImpl<$Res, WorkoutDaysMonth>;
  @useResult
  $Res call({DateTime month, Set<DateTime> trainedDays, int streak});
}

/// @nodoc
class _$WorkoutDaysMonthCopyWithImpl<$Res, $Val extends WorkoutDaysMonth>
    implements $WorkoutDaysMonthCopyWith<$Res> {
  _$WorkoutDaysMonthCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of WorkoutDaysMonth
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? month = null,
    Object? trainedDays = null,
    Object? streak = null,
  }) {
    return _then(_value.copyWith(
      month: null == month
          ? _value.month
          : month // ignore: cast_nullable_to_non_nullable
              as DateTime,
      trainedDays: null == trainedDays
          ? _value.trainedDays
          : trainedDays // ignore: cast_nullable_to_non_nullable
              as Set<DateTime>,
      streak: null == streak
          ? _value.streak
          : streak // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$WorkoutDaysMonthImplCopyWith<$Res>
    implements $WorkoutDaysMonthCopyWith<$Res> {
  factory _$$WorkoutDaysMonthImplCopyWith(_$WorkoutDaysMonthImpl value,
          $Res Function(_$WorkoutDaysMonthImpl) then) =
      __$$WorkoutDaysMonthImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({DateTime month, Set<DateTime> trainedDays, int streak});
}

/// @nodoc
class __$$WorkoutDaysMonthImplCopyWithImpl<$Res>
    extends _$WorkoutDaysMonthCopyWithImpl<$Res, _$WorkoutDaysMonthImpl>
    implements _$$WorkoutDaysMonthImplCopyWith<$Res> {
  __$$WorkoutDaysMonthImplCopyWithImpl(_$WorkoutDaysMonthImpl _value,
      $Res Function(_$WorkoutDaysMonthImpl) _then)
      : super(_value, _then);

  /// Create a copy of WorkoutDaysMonth
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? month = null,
    Object? trainedDays = null,
    Object? streak = null,
  }) {
    return _then(_$WorkoutDaysMonthImpl(
      month: null == month
          ? _value.month
          : month // ignore: cast_nullable_to_non_nullable
              as DateTime,
      trainedDays: null == trainedDays
          ? _value._trainedDays
          : trainedDays // ignore: cast_nullable_to_non_nullable
              as Set<DateTime>,
      streak: null == streak
          ? _value.streak
          : streak // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc

class _$WorkoutDaysMonthImpl implements _WorkoutDaysMonth {
  const _$WorkoutDaysMonthImpl(
      {required this.month,
      required final Set<DateTime> trainedDays,
      required this.streak})
      : _trainedDays = trainedDays;

  @override
  final DateTime month;
  final Set<DateTime> _trainedDays;
  @override
  Set<DateTime> get trainedDays {
    if (_trainedDays is EqualUnmodifiableSetView) return _trainedDays;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableSetView(_trainedDays);
  }

  @override
  final int streak;

  @override
  String toString() {
    return 'WorkoutDaysMonth(month: $month, trainedDays: $trainedDays, streak: $streak)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WorkoutDaysMonthImpl &&
            (identical(other.month, month) || other.month == month) &&
            const DeepCollectionEquality()
                .equals(other._trainedDays, _trainedDays) &&
            (identical(other.streak, streak) || other.streak == streak));
  }

  @override
  int get hashCode => Object.hash(runtimeType, month,
      const DeepCollectionEquality().hash(_trainedDays), streak);

  /// Create a copy of WorkoutDaysMonth
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$WorkoutDaysMonthImplCopyWith<_$WorkoutDaysMonthImpl> get copyWith =>
      __$$WorkoutDaysMonthImplCopyWithImpl<_$WorkoutDaysMonthImpl>(
          this, _$identity);
}

abstract class _WorkoutDaysMonth implements WorkoutDaysMonth {
  const factory _WorkoutDaysMonth(
      {required final DateTime month,
      required final Set<DateTime> trainedDays,
      required final int streak}) = _$WorkoutDaysMonthImpl;

  @override
  DateTime get month;
  @override
  Set<DateTime> get trainedDays;
  @override
  int get streak;

  /// Create a copy of WorkoutDaysMonth
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$WorkoutDaysMonthImplCopyWith<_$WorkoutDaysMonthImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
