// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'workout_snapshot.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

WorkoutSnapshot _$WorkoutSnapshotFromJson(Map<String, dynamic> json) {
  return _WorkoutSnapshot.fromJson(json);
}

/// @nodoc
mixin _$WorkoutSnapshot {
  /// Ejercicios en orden de primera aparición en la sesión, cada uno con
  /// sus [SetLog] completos — el render rehidrata y reusa
  /// `SessionExerciseBlock` tal cual, sin adaptadores.
  List<WorkoutSnapshotExercise> get exercises =>
      throw _privateConstructorUsedError;

  /// Sets por eje del radar, key = `RadarAxis.name` ('back', 'chest', …).
  /// Sparse — solo ejes con ≥1 set — igual que
  /// `SessionMuscleDistribution.setsByAxis`. Precomputado al compartir
  /// porque el viewer no puede resolver exerciseId → muscleGroup de
  /// ejercicios custom ajenos (la rutina del autor es privada).
  Map<String, int> get setsByAxis => throw _privateConstructorUsedError;

  /// Volumen (reps × kg) por eje del radar, misma key y sparseness que
  /// [setsByAxis].
  Map<String, double> get volumeKgByAxis => throw _privateConstructorUsedError;

  /// True si la sesión tenía más de [kMaxSnapshotExercises] ejercicios y
  /// la lista quedó truncada.
  bool get truncated => throw _privateConstructorUsedError;

  /// Serializes this WorkoutSnapshot to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of WorkoutSnapshot
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $WorkoutSnapshotCopyWith<WorkoutSnapshot> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $WorkoutSnapshotCopyWith<$Res> {
  factory $WorkoutSnapshotCopyWith(
          WorkoutSnapshot value, $Res Function(WorkoutSnapshot) then) =
      _$WorkoutSnapshotCopyWithImpl<$Res, WorkoutSnapshot>;
  @useResult
  $Res call(
      {List<WorkoutSnapshotExercise> exercises,
      Map<String, int> setsByAxis,
      Map<String, double> volumeKgByAxis,
      bool truncated});
}

/// @nodoc
class _$WorkoutSnapshotCopyWithImpl<$Res, $Val extends WorkoutSnapshot>
    implements $WorkoutSnapshotCopyWith<$Res> {
  _$WorkoutSnapshotCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of WorkoutSnapshot
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? exercises = null,
    Object? setsByAxis = null,
    Object? volumeKgByAxis = null,
    Object? truncated = null,
  }) {
    return _then(_value.copyWith(
      exercises: null == exercises
          ? _value.exercises
          : exercises // ignore: cast_nullable_to_non_nullable
              as List<WorkoutSnapshotExercise>,
      setsByAxis: null == setsByAxis
          ? _value.setsByAxis
          : setsByAxis // ignore: cast_nullable_to_non_nullable
              as Map<String, int>,
      volumeKgByAxis: null == volumeKgByAxis
          ? _value.volumeKgByAxis
          : volumeKgByAxis // ignore: cast_nullable_to_non_nullable
              as Map<String, double>,
      truncated: null == truncated
          ? _value.truncated
          : truncated // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$WorkoutSnapshotImplCopyWith<$Res>
    implements $WorkoutSnapshotCopyWith<$Res> {
  factory _$$WorkoutSnapshotImplCopyWith(_$WorkoutSnapshotImpl value,
          $Res Function(_$WorkoutSnapshotImpl) then) =
      __$$WorkoutSnapshotImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {List<WorkoutSnapshotExercise> exercises,
      Map<String, int> setsByAxis,
      Map<String, double> volumeKgByAxis,
      bool truncated});
}

/// @nodoc
class __$$WorkoutSnapshotImplCopyWithImpl<$Res>
    extends _$WorkoutSnapshotCopyWithImpl<$Res, _$WorkoutSnapshotImpl>
    implements _$$WorkoutSnapshotImplCopyWith<$Res> {
  __$$WorkoutSnapshotImplCopyWithImpl(
      _$WorkoutSnapshotImpl _value, $Res Function(_$WorkoutSnapshotImpl) _then)
      : super(_value, _then);

  /// Create a copy of WorkoutSnapshot
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? exercises = null,
    Object? setsByAxis = null,
    Object? volumeKgByAxis = null,
    Object? truncated = null,
  }) {
    return _then(_$WorkoutSnapshotImpl(
      exercises: null == exercises
          ? _value._exercises
          : exercises // ignore: cast_nullable_to_non_nullable
              as List<WorkoutSnapshotExercise>,
      setsByAxis: null == setsByAxis
          ? _value._setsByAxis
          : setsByAxis // ignore: cast_nullable_to_non_nullable
              as Map<String, int>,
      volumeKgByAxis: null == volumeKgByAxis
          ? _value._volumeKgByAxis
          : volumeKgByAxis // ignore: cast_nullable_to_non_nullable
              as Map<String, double>,
      truncated: null == truncated
          ? _value.truncated
          : truncated // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$WorkoutSnapshotImpl implements _WorkoutSnapshot {
  const _$WorkoutSnapshotImpl(
      {required final List<WorkoutSnapshotExercise> exercises,
      final Map<String, int> setsByAxis = const <String, int>{},
      final Map<String, double> volumeKgByAxis = const <String, double>{},
      this.truncated = false})
      : _exercises = exercises,
        _setsByAxis = setsByAxis,
        _volumeKgByAxis = volumeKgByAxis;

  factory _$WorkoutSnapshotImpl.fromJson(Map<String, dynamic> json) =>
      _$$WorkoutSnapshotImplFromJson(json);

  /// Ejercicios en orden de primera aparición en la sesión, cada uno con
  /// sus [SetLog] completos — el render rehidrata y reusa
  /// `SessionExerciseBlock` tal cual, sin adaptadores.
  final List<WorkoutSnapshotExercise> _exercises;

  /// Ejercicios en orden de primera aparición en la sesión, cada uno con
  /// sus [SetLog] completos — el render rehidrata y reusa
  /// `SessionExerciseBlock` tal cual, sin adaptadores.
  @override
  List<WorkoutSnapshotExercise> get exercises {
    if (_exercises is EqualUnmodifiableListView) return _exercises;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_exercises);
  }

  /// Sets por eje del radar, key = `RadarAxis.name` ('back', 'chest', …).
  /// Sparse — solo ejes con ≥1 set — igual que
  /// `SessionMuscleDistribution.setsByAxis`. Precomputado al compartir
  /// porque el viewer no puede resolver exerciseId → muscleGroup de
  /// ejercicios custom ajenos (la rutina del autor es privada).
  final Map<String, int> _setsByAxis;

  /// Sets por eje del radar, key = `RadarAxis.name` ('back', 'chest', …).
  /// Sparse — solo ejes con ≥1 set — igual que
  /// `SessionMuscleDistribution.setsByAxis`. Precomputado al compartir
  /// porque el viewer no puede resolver exerciseId → muscleGroup de
  /// ejercicios custom ajenos (la rutina del autor es privada).
  @override
  @JsonKey()
  Map<String, int> get setsByAxis {
    if (_setsByAxis is EqualUnmodifiableMapView) return _setsByAxis;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_setsByAxis);
  }

  /// Volumen (reps × kg) por eje del radar, misma key y sparseness que
  /// [setsByAxis].
  final Map<String, double> _volumeKgByAxis;

  /// Volumen (reps × kg) por eje del radar, misma key y sparseness que
  /// [setsByAxis].
  @override
  @JsonKey()
  Map<String, double> get volumeKgByAxis {
    if (_volumeKgByAxis is EqualUnmodifiableMapView) return _volumeKgByAxis;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_volumeKgByAxis);
  }

  /// True si la sesión tenía más de [kMaxSnapshotExercises] ejercicios y
  /// la lista quedó truncada.
  @override
  @JsonKey()
  final bool truncated;

  @override
  String toString() {
    return 'WorkoutSnapshot(exercises: $exercises, setsByAxis: $setsByAxis, volumeKgByAxis: $volumeKgByAxis, truncated: $truncated)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WorkoutSnapshotImpl &&
            const DeepCollectionEquality()
                .equals(other._exercises, _exercises) &&
            const DeepCollectionEquality()
                .equals(other._setsByAxis, _setsByAxis) &&
            const DeepCollectionEquality()
                .equals(other._volumeKgByAxis, _volumeKgByAxis) &&
            (identical(other.truncated, truncated) ||
                other.truncated == truncated));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(_exercises),
      const DeepCollectionEquality().hash(_setsByAxis),
      const DeepCollectionEquality().hash(_volumeKgByAxis),
      truncated);

  /// Create a copy of WorkoutSnapshot
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$WorkoutSnapshotImplCopyWith<_$WorkoutSnapshotImpl> get copyWith =>
      __$$WorkoutSnapshotImplCopyWithImpl<_$WorkoutSnapshotImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$WorkoutSnapshotImplToJson(
      this,
    );
  }
}

abstract class _WorkoutSnapshot implements WorkoutSnapshot {
  const factory _WorkoutSnapshot(
      {required final List<WorkoutSnapshotExercise> exercises,
      final Map<String, int> setsByAxis,
      final Map<String, double> volumeKgByAxis,
      final bool truncated}) = _$WorkoutSnapshotImpl;

  factory _WorkoutSnapshot.fromJson(Map<String, dynamic> json) =
      _$WorkoutSnapshotImpl.fromJson;

  /// Ejercicios en orden de primera aparición en la sesión, cada uno con
  /// sus [SetLog] completos — el render rehidrata y reusa
  /// `SessionExerciseBlock` tal cual, sin adaptadores.
  @override
  List<WorkoutSnapshotExercise> get exercises;

  /// Sets por eje del radar, key = `RadarAxis.name` ('back', 'chest', …).
  /// Sparse — solo ejes con ≥1 set — igual que
  /// `SessionMuscleDistribution.setsByAxis`. Precomputado al compartir
  /// porque el viewer no puede resolver exerciseId → muscleGroup de
  /// ejercicios custom ajenos (la rutina del autor es privada).
  @override
  Map<String, int> get setsByAxis;

  /// Volumen (reps × kg) por eje del radar, misma key y sparseness que
  /// [setsByAxis].
  @override
  Map<String, double> get volumeKgByAxis;

  /// True si la sesión tenía más de [kMaxSnapshotExercises] ejercicios y
  /// la lista quedó truncada.
  @override
  bool get truncated;

  /// Create a copy of WorkoutSnapshot
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$WorkoutSnapshotImplCopyWith<_$WorkoutSnapshotImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

WorkoutSnapshotExercise _$WorkoutSnapshotExerciseFromJson(
    Map<String, dynamic> json) {
  return _WorkoutSnapshotExercise.fromJson(json);
}

/// @nodoc
mixin _$WorkoutSnapshotExercise {
  String get exerciseName => throw _privateConstructorUsedError;
  List<SetLog> get sets => throw _privateConstructorUsedError;

  /// Serializes this WorkoutSnapshotExercise to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of WorkoutSnapshotExercise
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $WorkoutSnapshotExerciseCopyWith<WorkoutSnapshotExercise> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $WorkoutSnapshotExerciseCopyWith<$Res> {
  factory $WorkoutSnapshotExerciseCopyWith(WorkoutSnapshotExercise value,
          $Res Function(WorkoutSnapshotExercise) then) =
      _$WorkoutSnapshotExerciseCopyWithImpl<$Res, WorkoutSnapshotExercise>;
  @useResult
  $Res call({String exerciseName, List<SetLog> sets});
}

/// @nodoc
class _$WorkoutSnapshotExerciseCopyWithImpl<$Res,
        $Val extends WorkoutSnapshotExercise>
    implements $WorkoutSnapshotExerciseCopyWith<$Res> {
  _$WorkoutSnapshotExerciseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of WorkoutSnapshotExercise
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? exerciseName = null,
    Object? sets = null,
  }) {
    return _then(_value.copyWith(
      exerciseName: null == exerciseName
          ? _value.exerciseName
          : exerciseName // ignore: cast_nullable_to_non_nullable
              as String,
      sets: null == sets
          ? _value.sets
          : sets // ignore: cast_nullable_to_non_nullable
              as List<SetLog>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$WorkoutSnapshotExerciseImplCopyWith<$Res>
    implements $WorkoutSnapshotExerciseCopyWith<$Res> {
  factory _$$WorkoutSnapshotExerciseImplCopyWith(
          _$WorkoutSnapshotExerciseImpl value,
          $Res Function(_$WorkoutSnapshotExerciseImpl) then) =
      __$$WorkoutSnapshotExerciseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String exerciseName, List<SetLog> sets});
}

/// @nodoc
class __$$WorkoutSnapshotExerciseImplCopyWithImpl<$Res>
    extends _$WorkoutSnapshotExerciseCopyWithImpl<$Res,
        _$WorkoutSnapshotExerciseImpl>
    implements _$$WorkoutSnapshotExerciseImplCopyWith<$Res> {
  __$$WorkoutSnapshotExerciseImplCopyWithImpl(
      _$WorkoutSnapshotExerciseImpl _value,
      $Res Function(_$WorkoutSnapshotExerciseImpl) _then)
      : super(_value, _then);

  /// Create a copy of WorkoutSnapshotExercise
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? exerciseName = null,
    Object? sets = null,
  }) {
    return _then(_$WorkoutSnapshotExerciseImpl(
      exerciseName: null == exerciseName
          ? _value.exerciseName
          : exerciseName // ignore: cast_nullable_to_non_nullable
              as String,
      sets: null == sets
          ? _value._sets
          : sets // ignore: cast_nullable_to_non_nullable
              as List<SetLog>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$WorkoutSnapshotExerciseImpl implements _WorkoutSnapshotExercise {
  const _$WorkoutSnapshotExerciseImpl(
      {required this.exerciseName, required final List<SetLog> sets})
      : _sets = sets;

  factory _$WorkoutSnapshotExerciseImpl.fromJson(Map<String, dynamic> json) =>
      _$$WorkoutSnapshotExerciseImplFromJson(json);

  @override
  final String exerciseName;
  final List<SetLog> _sets;
  @override
  List<SetLog> get sets {
    if (_sets is EqualUnmodifiableListView) return _sets;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_sets);
  }

  @override
  String toString() {
    return 'WorkoutSnapshotExercise(exerciseName: $exerciseName, sets: $sets)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WorkoutSnapshotExerciseImpl &&
            (identical(other.exerciseName, exerciseName) ||
                other.exerciseName == exerciseName) &&
            const DeepCollectionEquality().equals(other._sets, _sets));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType, exerciseName, const DeepCollectionEquality().hash(_sets));

  /// Create a copy of WorkoutSnapshotExercise
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$WorkoutSnapshotExerciseImplCopyWith<_$WorkoutSnapshotExerciseImpl>
      get copyWith => __$$WorkoutSnapshotExerciseImplCopyWithImpl<
          _$WorkoutSnapshotExerciseImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$WorkoutSnapshotExerciseImplToJson(
      this,
    );
  }
}

abstract class _WorkoutSnapshotExercise implements WorkoutSnapshotExercise {
  const factory _WorkoutSnapshotExercise(
      {required final String exerciseName,
      required final List<SetLog> sets}) = _$WorkoutSnapshotExerciseImpl;

  factory _WorkoutSnapshotExercise.fromJson(Map<String, dynamic> json) =
      _$WorkoutSnapshotExerciseImpl.fromJson;

  @override
  String get exerciseName;
  @override
  List<SetLog> get sets;

  /// Create a copy of WorkoutSnapshotExercise
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$WorkoutSnapshotExerciseImplCopyWith<_$WorkoutSnapshotExerciseImpl>
      get copyWith => throw _privateConstructorUsedError;
}
