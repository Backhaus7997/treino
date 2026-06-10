// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'routine_slot.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

RoutineSlot _$RoutineSlotFromJson(Map<String, dynamic> json) {
  return _RoutineSlot.fromJson(json);
}

/// @nodoc
mixin _$RoutineSlot {
  String get exerciseId =>
      throw _privateConstructorUsedError; // FK → exercises/{id} (canonical reference)
  String get exerciseName =>
      throw _privateConstructorUsedError; // denormalized for compact card display (ADR-2)
  String get muscleGroup =>
      throw _privateConstructorUsedError; // denormalized for compact card display
  int get targetSets => throw _privateConstructorUsedError;
  int get targetRepsMin => throw _privateConstructorUsedError;
  int get targetRepsMax => throw _privateConstructorUsedError;
  int get restSeconds => throw _privateConstructorUsedError;
  double? get targetWeightKg =>
      throw _privateConstructorUsedError; // null means "user picks" or "no target" (plate math)
  String? get notes =>
      throw _privateConstructorUsedError; // nullable free-form coaching notes
  int? get supersetGroup =>
      throw _privateConstructorUsedError; // non-null → slot belongs to a superset block
// ── Existing additive fields (kept for backward compat) ──────────────────
// Per-set reps: [] = none/legacy; [10] = uniform; [6,8,10] = per-set.
  List<int> get targetReps =>
      throw _privateConstructorUsedError; // null / 0 = reps-based; > 0 = time-based (seconds per set).
  int? get durationSeconds =>
      throw _privateConstructorUsedError; // ── Phase-1 additions: Hevy per-set-row model ────────────────────────────
  /// Whether each set is reps-based or duration-based.
  /// Unknown values on read fall back to [ExerciseMode.reps].
  @JsonKey(unknownEnumValue: ExerciseMode.reps)
  ExerciseMode get exerciseMode => throw _privateConstructorUsedError;

  /// Whether the rep target is a single count or a min–max range.
  /// Unknown values on read fall back to [RepMode.single].
  @JsonKey(unknownEnumValue: RepMode.single)
  RepMode get repMode => throw _privateConstructorUsedError;

  /// The explicit per-set rows for this slot.
  /// Empty list = use legacy fields and synthesize via [effectiveSets].
  List<SetSpec> get sets => throw _privateConstructorUsedError;

  /// Periodization (Model B): per-week explicit set rows.
  /// `weeklySets[w]` holds the prescription for 0-based week `w`.
  /// Empty = legacy / single-week slot → resolve via [effectiveSets].
  List<List<SetSpec>> get weeklySets => throw _privateConstructorUsedError;

  /// Serializes this RoutineSlot to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of RoutineSlot
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $RoutineSlotCopyWith<RoutineSlot> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $RoutineSlotCopyWith<$Res> {
  factory $RoutineSlotCopyWith(
          RoutineSlot value, $Res Function(RoutineSlot) then) =
      _$RoutineSlotCopyWithImpl<$Res, RoutineSlot>;
  @useResult
  $Res call(
      {String exerciseId,
      String exerciseName,
      String muscleGroup,
      int targetSets,
      int targetRepsMin,
      int targetRepsMax,
      int restSeconds,
      double? targetWeightKg,
      String? notes,
      int? supersetGroup,
      List<int> targetReps,
      int? durationSeconds,
      @JsonKey(unknownEnumValue: ExerciseMode.reps) ExerciseMode exerciseMode,
      @JsonKey(unknownEnumValue: RepMode.single) RepMode repMode,
      List<SetSpec> sets,
      List<List<SetSpec>> weeklySets});
}

/// @nodoc
class _$RoutineSlotCopyWithImpl<$Res, $Val extends RoutineSlot>
    implements $RoutineSlotCopyWith<$Res> {
  _$RoutineSlotCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of RoutineSlot
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? exerciseId = null,
    Object? exerciseName = null,
    Object? muscleGroup = null,
    Object? targetSets = null,
    Object? targetRepsMin = null,
    Object? targetRepsMax = null,
    Object? restSeconds = null,
    Object? targetWeightKg = freezed,
    Object? notes = freezed,
    Object? supersetGroup = freezed,
    Object? targetReps = null,
    Object? durationSeconds = freezed,
    Object? exerciseMode = null,
    Object? repMode = null,
    Object? sets = null,
    Object? weeklySets = null,
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
      muscleGroup: null == muscleGroup
          ? _value.muscleGroup
          : muscleGroup // ignore: cast_nullable_to_non_nullable
              as String,
      targetSets: null == targetSets
          ? _value.targetSets
          : targetSets // ignore: cast_nullable_to_non_nullable
              as int,
      targetRepsMin: null == targetRepsMin
          ? _value.targetRepsMin
          : targetRepsMin // ignore: cast_nullable_to_non_nullable
              as int,
      targetRepsMax: null == targetRepsMax
          ? _value.targetRepsMax
          : targetRepsMax // ignore: cast_nullable_to_non_nullable
              as int,
      restSeconds: null == restSeconds
          ? _value.restSeconds
          : restSeconds // ignore: cast_nullable_to_non_nullable
              as int,
      targetWeightKg: freezed == targetWeightKg
          ? _value.targetWeightKg
          : targetWeightKg // ignore: cast_nullable_to_non_nullable
              as double?,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
      supersetGroup: freezed == supersetGroup
          ? _value.supersetGroup
          : supersetGroup // ignore: cast_nullable_to_non_nullable
              as int?,
      targetReps: null == targetReps
          ? _value.targetReps
          : targetReps // ignore: cast_nullable_to_non_nullable
              as List<int>,
      durationSeconds: freezed == durationSeconds
          ? _value.durationSeconds
          : durationSeconds // ignore: cast_nullable_to_non_nullable
              as int?,
      exerciseMode: null == exerciseMode
          ? _value.exerciseMode
          : exerciseMode // ignore: cast_nullable_to_non_nullable
              as ExerciseMode,
      repMode: null == repMode
          ? _value.repMode
          : repMode // ignore: cast_nullable_to_non_nullable
              as RepMode,
      sets: null == sets
          ? _value.sets
          : sets // ignore: cast_nullable_to_non_nullable
              as List<SetSpec>,
      weeklySets: null == weeklySets
          ? _value.weeklySets
          : weeklySets // ignore: cast_nullable_to_non_nullable
              as List<List<SetSpec>>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$RoutineSlotImplCopyWith<$Res>
    implements $RoutineSlotCopyWith<$Res> {
  factory _$$RoutineSlotImplCopyWith(
          _$RoutineSlotImpl value, $Res Function(_$RoutineSlotImpl) then) =
      __$$RoutineSlotImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String exerciseId,
      String exerciseName,
      String muscleGroup,
      int targetSets,
      int targetRepsMin,
      int targetRepsMax,
      int restSeconds,
      double? targetWeightKg,
      String? notes,
      int? supersetGroup,
      List<int> targetReps,
      int? durationSeconds,
      @JsonKey(unknownEnumValue: ExerciseMode.reps) ExerciseMode exerciseMode,
      @JsonKey(unknownEnumValue: RepMode.single) RepMode repMode,
      List<SetSpec> sets,
      List<List<SetSpec>> weeklySets});
}

/// @nodoc
class __$$RoutineSlotImplCopyWithImpl<$Res>
    extends _$RoutineSlotCopyWithImpl<$Res, _$RoutineSlotImpl>
    implements _$$RoutineSlotImplCopyWith<$Res> {
  __$$RoutineSlotImplCopyWithImpl(
      _$RoutineSlotImpl _value, $Res Function(_$RoutineSlotImpl) _then)
      : super(_value, _then);

  /// Create a copy of RoutineSlot
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? exerciseId = null,
    Object? exerciseName = null,
    Object? muscleGroup = null,
    Object? targetSets = null,
    Object? targetRepsMin = null,
    Object? targetRepsMax = null,
    Object? restSeconds = null,
    Object? targetWeightKg = freezed,
    Object? notes = freezed,
    Object? supersetGroup = freezed,
    Object? targetReps = null,
    Object? durationSeconds = freezed,
    Object? exerciseMode = null,
    Object? repMode = null,
    Object? sets = null,
    Object? weeklySets = null,
  }) {
    return _then(_$RoutineSlotImpl(
      exerciseId: null == exerciseId
          ? _value.exerciseId
          : exerciseId // ignore: cast_nullable_to_non_nullable
              as String,
      exerciseName: null == exerciseName
          ? _value.exerciseName
          : exerciseName // ignore: cast_nullable_to_non_nullable
              as String,
      muscleGroup: null == muscleGroup
          ? _value.muscleGroup
          : muscleGroup // ignore: cast_nullable_to_non_nullable
              as String,
      targetSets: null == targetSets
          ? _value.targetSets
          : targetSets // ignore: cast_nullable_to_non_nullable
              as int,
      targetRepsMin: null == targetRepsMin
          ? _value.targetRepsMin
          : targetRepsMin // ignore: cast_nullable_to_non_nullable
              as int,
      targetRepsMax: null == targetRepsMax
          ? _value.targetRepsMax
          : targetRepsMax // ignore: cast_nullable_to_non_nullable
              as int,
      restSeconds: null == restSeconds
          ? _value.restSeconds
          : restSeconds // ignore: cast_nullable_to_non_nullable
              as int,
      targetWeightKg: freezed == targetWeightKg
          ? _value.targetWeightKg
          : targetWeightKg // ignore: cast_nullable_to_non_nullable
              as double?,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
      supersetGroup: freezed == supersetGroup
          ? _value.supersetGroup
          : supersetGroup // ignore: cast_nullable_to_non_nullable
              as int?,
      targetReps: null == targetReps
          ? _value._targetReps
          : targetReps // ignore: cast_nullable_to_non_nullable
              as List<int>,
      durationSeconds: freezed == durationSeconds
          ? _value.durationSeconds
          : durationSeconds // ignore: cast_nullable_to_non_nullable
              as int?,
      exerciseMode: null == exerciseMode
          ? _value.exerciseMode
          : exerciseMode // ignore: cast_nullable_to_non_nullable
              as ExerciseMode,
      repMode: null == repMode
          ? _value.repMode
          : repMode // ignore: cast_nullable_to_non_nullable
              as RepMode,
      sets: null == sets
          ? _value._sets
          : sets // ignore: cast_nullable_to_non_nullable
              as List<SetSpec>,
      weeklySets: null == weeklySets
          ? _value._weeklySets
          : weeklySets // ignore: cast_nullable_to_non_nullable
              as List<List<SetSpec>>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$RoutineSlotImpl extends _RoutineSlot {
  const _$RoutineSlotImpl(
      {required this.exerciseId,
      required this.exerciseName,
      required this.muscleGroup,
      required this.targetSets,
      required this.targetRepsMin,
      required this.targetRepsMax,
      required this.restSeconds,
      this.targetWeightKg,
      this.notes,
      this.supersetGroup,
      final List<int> targetReps = const <int>[],
      this.durationSeconds,
      @JsonKey(unknownEnumValue: ExerciseMode.reps)
      this.exerciseMode = ExerciseMode.reps,
      @JsonKey(unknownEnumValue: RepMode.single) this.repMode = RepMode.single,
      final List<SetSpec> sets = const <SetSpec>[],
      final List<List<SetSpec>> weeklySets = const <List<SetSpec>>[]})
      : _targetReps = targetReps,
        _sets = sets,
        _weeklySets = weeklySets,
        super._();

  factory _$RoutineSlotImpl.fromJson(Map<String, dynamic> json) =>
      _$$RoutineSlotImplFromJson(json);

  @override
  final String exerciseId;
// FK → exercises/{id} (canonical reference)
  @override
  final String exerciseName;
// denormalized for compact card display (ADR-2)
  @override
  final String muscleGroup;
// denormalized for compact card display
  @override
  final int targetSets;
  @override
  final int targetRepsMin;
  @override
  final int targetRepsMax;
  @override
  final int restSeconds;
  @override
  final double? targetWeightKg;
// null means "user picks" or "no target" (plate math)
  @override
  final String? notes;
// nullable free-form coaching notes
  @override
  final int? supersetGroup;
// non-null → slot belongs to a superset block
// ── Existing additive fields (kept for backward compat) ──────────────────
// Per-set reps: [] = none/legacy; [10] = uniform; [6,8,10] = per-set.
  final List<int> _targetReps;
// non-null → slot belongs to a superset block
// ── Existing additive fields (kept for backward compat) ──────────────────
// Per-set reps: [] = none/legacy; [10] = uniform; [6,8,10] = per-set.
  @override
  @JsonKey()
  List<int> get targetReps {
    if (_targetReps is EqualUnmodifiableListView) return _targetReps;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_targetReps);
  }

// null / 0 = reps-based; > 0 = time-based (seconds per set).
  @override
  final int? durationSeconds;
// ── Phase-1 additions: Hevy per-set-row model ────────────────────────────
  /// Whether each set is reps-based or duration-based.
  /// Unknown values on read fall back to [ExerciseMode.reps].
  @override
  @JsonKey(unknownEnumValue: ExerciseMode.reps)
  final ExerciseMode exerciseMode;

  /// Whether the rep target is a single count or a min–max range.
  /// Unknown values on read fall back to [RepMode.single].
  @override
  @JsonKey(unknownEnumValue: RepMode.single)
  final RepMode repMode;

  /// The explicit per-set rows for this slot.
  /// Empty list = use legacy fields and synthesize via [effectiveSets].
  final List<SetSpec> _sets;

  /// The explicit per-set rows for this slot.
  /// Empty list = use legacy fields and synthesize via [effectiveSets].
  @override
  @JsonKey()
  List<SetSpec> get sets {
    if (_sets is EqualUnmodifiableListView) return _sets;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_sets);
  }

  /// Periodization (Model B): per-week explicit set rows.
  /// `weeklySets[w]` holds the prescription for 0-based week `w`.
  /// Empty = legacy / single-week slot → resolve via [effectiveSets].
  final List<List<SetSpec>> _weeklySets;

  /// Periodization (Model B): per-week explicit set rows.
  /// `weeklySets[w]` holds the prescription for 0-based week `w`.
  /// Empty = legacy / single-week slot → resolve via [effectiveSets].
  @override
  @JsonKey()
  List<List<SetSpec>> get weeklySets {
    if (_weeklySets is EqualUnmodifiableListView) return _weeklySets;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_weeklySets);
  }

  @override
  String toString() {
    return 'RoutineSlot(exerciseId: $exerciseId, exerciseName: $exerciseName, muscleGroup: $muscleGroup, targetSets: $targetSets, targetRepsMin: $targetRepsMin, targetRepsMax: $targetRepsMax, restSeconds: $restSeconds, targetWeightKg: $targetWeightKg, notes: $notes, supersetGroup: $supersetGroup, targetReps: $targetReps, durationSeconds: $durationSeconds, exerciseMode: $exerciseMode, repMode: $repMode, sets: $sets, weeklySets: $weeklySets)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$RoutineSlotImpl &&
            (identical(other.exerciseId, exerciseId) ||
                other.exerciseId == exerciseId) &&
            (identical(other.exerciseName, exerciseName) ||
                other.exerciseName == exerciseName) &&
            (identical(other.muscleGroup, muscleGroup) ||
                other.muscleGroup == muscleGroup) &&
            (identical(other.targetSets, targetSets) ||
                other.targetSets == targetSets) &&
            (identical(other.targetRepsMin, targetRepsMin) ||
                other.targetRepsMin == targetRepsMin) &&
            (identical(other.targetRepsMax, targetRepsMax) ||
                other.targetRepsMax == targetRepsMax) &&
            (identical(other.restSeconds, restSeconds) ||
                other.restSeconds == restSeconds) &&
            (identical(other.targetWeightKg, targetWeightKg) ||
                other.targetWeightKg == targetWeightKg) &&
            (identical(other.notes, notes) || other.notes == notes) &&
            (identical(other.supersetGroup, supersetGroup) ||
                other.supersetGroup == supersetGroup) &&
            const DeepCollectionEquality()
                .equals(other._targetReps, _targetReps) &&
            (identical(other.durationSeconds, durationSeconds) ||
                other.durationSeconds == durationSeconds) &&
            (identical(other.exerciseMode, exerciseMode) ||
                other.exerciseMode == exerciseMode) &&
            (identical(other.repMode, repMode) || other.repMode == repMode) &&
            const DeepCollectionEquality().equals(other._sets, _sets) &&
            const DeepCollectionEquality()
                .equals(other._weeklySets, _weeklySets));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      exerciseId,
      exerciseName,
      muscleGroup,
      targetSets,
      targetRepsMin,
      targetRepsMax,
      restSeconds,
      targetWeightKg,
      notes,
      supersetGroup,
      const DeepCollectionEquality().hash(_targetReps),
      durationSeconds,
      exerciseMode,
      repMode,
      const DeepCollectionEquality().hash(_sets),
      const DeepCollectionEquality().hash(_weeklySets));

  /// Create a copy of RoutineSlot
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$RoutineSlotImplCopyWith<_$RoutineSlotImpl> get copyWith =>
      __$$RoutineSlotImplCopyWithImpl<_$RoutineSlotImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$RoutineSlotImplToJson(
      this,
    );
  }
}

abstract class _RoutineSlot extends RoutineSlot {
  const factory _RoutineSlot(
      {required final String exerciseId,
      required final String exerciseName,
      required final String muscleGroup,
      required final int targetSets,
      required final int targetRepsMin,
      required final int targetRepsMax,
      required final int restSeconds,
      final double? targetWeightKg,
      final String? notes,
      final int? supersetGroup,
      final List<int> targetReps,
      final int? durationSeconds,
      @JsonKey(unknownEnumValue: ExerciseMode.reps)
      final ExerciseMode exerciseMode,
      @JsonKey(unknownEnumValue: RepMode.single) final RepMode repMode,
      final List<SetSpec> sets,
      final List<List<SetSpec>> weeklySets}) = _$RoutineSlotImpl;
  const _RoutineSlot._() : super._();

  factory _RoutineSlot.fromJson(Map<String, dynamic> json) =
      _$RoutineSlotImpl.fromJson;

  @override
  String get exerciseId; // FK → exercises/{id} (canonical reference)
  @override
  String get exerciseName; // denormalized for compact card display (ADR-2)
  @override
  String get muscleGroup; // denormalized for compact card display
  @override
  int get targetSets;
  @override
  int get targetRepsMin;
  @override
  int get targetRepsMax;
  @override
  int get restSeconds;
  @override
  double?
      get targetWeightKg; // null means "user picks" or "no target" (plate math)
  @override
  String? get notes; // nullable free-form coaching notes
  @override
  int? get supersetGroup; // non-null → slot belongs to a superset block
// ── Existing additive fields (kept for backward compat) ──────────────────
// Per-set reps: [] = none/legacy; [10] = uniform; [6,8,10] = per-set.
  @override
  List<int>
      get targetReps; // null / 0 = reps-based; > 0 = time-based (seconds per set).
  @override
  int?
      get durationSeconds; // ── Phase-1 additions: Hevy per-set-row model ────────────────────────────
  /// Whether each set is reps-based or duration-based.
  /// Unknown values on read fall back to [ExerciseMode.reps].
  @override
  @JsonKey(unknownEnumValue: ExerciseMode.reps)
  ExerciseMode get exerciseMode;

  /// Whether the rep target is a single count or a min–max range.
  /// Unknown values on read fall back to [RepMode.single].
  @override
  @JsonKey(unknownEnumValue: RepMode.single)
  RepMode get repMode;

  /// The explicit per-set rows for this slot.
  /// Empty list = use legacy fields and synthesize via [effectiveSets].
  @override
  List<SetSpec> get sets;

  /// Periodization (Model B): per-week explicit set rows.
  /// `weeklySets[w]` holds the prescription for 0-based week `w`.
  /// Empty = legacy / single-week slot → resolve via [effectiveSets].
  @override
  List<List<SetSpec>> get weeklySets;

  /// Create a copy of RoutineSlot
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$RoutineSlotImplCopyWith<_$RoutineSlotImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
