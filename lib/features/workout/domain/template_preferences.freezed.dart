// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'template_preferences.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

TemplatePreferences _$TemplatePreferencesFromJson(Map<String, dynamic> json) {
  return _TemplatePreferences.fromJson(json);
}

/// @nodoc
mixin _$TemplatePreferences {
  /// 2..6. Null ⇒ not answered.
  int? get daysPerWeek => throw _privateConstructorUsedError;

  /// 30 / 45 / 60 / 75, where 75 means "75 or more" — the handoff's last
  /// option is "75 MIN O MÁS". Stored as the lower bound so a future finer
  /// scale stays comparable. Null ⇒ not answered.
  int? get minutesPerSession => throw _privateConstructorUsedError;

  /// Objetivos del atleta. Vacío ⇒ no respondió (NEUTRO, nunca excluye).
  ///
  /// ── Era uno solo, ahora son varios (2026-10-09, pedido del owner) ──────
  /// Antes esto era un `RoutineGoal? goal` a propósito: la idea era que "para
  /// qué entreno ahora" tenía una sola respuesta, y que lo multi-valor era
  /// cosa de la plantilla (`Routine.goals`, #635 PR#1). En uso real no se
  /// sostuvo: "salud y estética" es una respuesta legítima, y obligar a
  /// elegir una dejaba afuera a la mitad de lo que el atleta busca.
  ///
  /// ── Compatibilidad con la 1.0 de la App Store ─────────────────────────
  /// La 1.0 lee y escribe este mismo mapa y sólo conoce `goal`. Por eso:
  ///
  ///   * LEER: si `goals` falta o viene vacío y existe el `goal` legacy, vale
  ///     `[goal]` ([_readGoals]). Un atleta que respondió en la 1.0 no pierde
  ///     su respuesta al actualizar.
  ///   * ESCRIBIR: [toJson] manda `goals` Y `goal` = el primero elegido (o
  ///     null). La 1.0 sigue leyendo un valor con sentido.
  ///   * Si la 1.0 vuelve a guardar, escribe sólo `goal`. Ojo: NO reemplaza el
  ///     mapa. `UserRepository.update` persiste con `set(..., merge: true)` y
  ///     Firestore mergea los mapas anidados en profundidad, así que el
  ///     `goals` viejo SOBREVIVE junto al `goal` nuevo. La lectura lo
  ///     reconcilia con esta invariante: el cliente nuevo escribe SIEMPRE
  ///     `goal == goals.first` (o null si no hay). Si no coinciden, alguien
  ///     que sólo conoce `goal` editó después, y gana `goal` ([_readGoals]).
  ///
  /// [RoutineGoalListConverter] no es decoración: descarta los valores que no
  /// conoce en vez de tirar. Este modelo se decodifica como parte de
  /// `UserProfile`, así que un objetivo agregado por un build más nuevo, si
  /// tirara, rompería el stream del perfil entero en los clientes viejos y los
  /// mandaría a `/profile-unavailable` (#544).
// ignore: invalid_annotation_target
  @JsonKey(readValue: _readGoals)
  @RoutineGoalListConverter()
  List<RoutineGoal> get goals => throw _privateConstructorUsedError;

  /// Canonical [MuscleGroup] keys (`chest`, `back`, `quads`…) — the app's one
  /// muscle vocabulary, reused rather than re-invented. Empty ⇒ no priority,
  /// which the handoff marks as explicitly optional ("Zonas a priorizar ·
  /// opcional").
  List<String> get priorityMuscleGroups => throw _privateConstructorUsedError;

  /// Create a copy of TemplatePreferences
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $TemplatePreferencesCopyWith<TemplatePreferences> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TemplatePreferencesCopyWith<$Res> {
  factory $TemplatePreferencesCopyWith(
          TemplatePreferences value, $Res Function(TemplatePreferences) then) =
      _$TemplatePreferencesCopyWithImpl<$Res, TemplatePreferences>;
  @useResult
  $Res call(
      {int? daysPerWeek,
      int? minutesPerSession,
      @JsonKey(readValue: _readGoals)
      @RoutineGoalListConverter()
      List<RoutineGoal> goals,
      List<String> priorityMuscleGroups});
}

/// @nodoc
class _$TemplatePreferencesCopyWithImpl<$Res, $Val extends TemplatePreferences>
    implements $TemplatePreferencesCopyWith<$Res> {
  _$TemplatePreferencesCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of TemplatePreferences
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? daysPerWeek = freezed,
    Object? minutesPerSession = freezed,
    Object? goals = null,
    Object? priorityMuscleGroups = null,
  }) {
    return _then(_value.copyWith(
      daysPerWeek: freezed == daysPerWeek
          ? _value.daysPerWeek
          : daysPerWeek // ignore: cast_nullable_to_non_nullable
              as int?,
      minutesPerSession: freezed == minutesPerSession
          ? _value.minutesPerSession
          : minutesPerSession // ignore: cast_nullable_to_non_nullable
              as int?,
      goals: null == goals
          ? _value.goals
          : goals // ignore: cast_nullable_to_non_nullable
              as List<RoutineGoal>,
      priorityMuscleGroups: null == priorityMuscleGroups
          ? _value.priorityMuscleGroups
          : priorityMuscleGroups // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$TemplatePreferencesImplCopyWith<$Res>
    implements $TemplatePreferencesCopyWith<$Res> {
  factory _$$TemplatePreferencesImplCopyWith(_$TemplatePreferencesImpl value,
          $Res Function(_$TemplatePreferencesImpl) then) =
      __$$TemplatePreferencesImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {int? daysPerWeek,
      int? minutesPerSession,
      @JsonKey(readValue: _readGoals)
      @RoutineGoalListConverter()
      List<RoutineGoal> goals,
      List<String> priorityMuscleGroups});
}

/// @nodoc
class __$$TemplatePreferencesImplCopyWithImpl<$Res>
    extends _$TemplatePreferencesCopyWithImpl<$Res, _$TemplatePreferencesImpl>
    implements _$$TemplatePreferencesImplCopyWith<$Res> {
  __$$TemplatePreferencesImplCopyWithImpl(_$TemplatePreferencesImpl _value,
      $Res Function(_$TemplatePreferencesImpl) _then)
      : super(_value, _then);

  /// Create a copy of TemplatePreferences
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? daysPerWeek = freezed,
    Object? minutesPerSession = freezed,
    Object? goals = null,
    Object? priorityMuscleGroups = null,
  }) {
    return _then(_$TemplatePreferencesImpl(
      daysPerWeek: freezed == daysPerWeek
          ? _value.daysPerWeek
          : daysPerWeek // ignore: cast_nullable_to_non_nullable
              as int?,
      minutesPerSession: freezed == minutesPerSession
          ? _value.minutesPerSession
          : minutesPerSession // ignore: cast_nullable_to_non_nullable
              as int?,
      goals: null == goals
          ? _value._goals
          : goals // ignore: cast_nullable_to_non_nullable
              as List<RoutineGoal>,
      priorityMuscleGroups: null == priorityMuscleGroups
          ? _value._priorityMuscleGroups
          : priorityMuscleGroups // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ));
  }
}

/// @nodoc
@JsonSerializable(createToJson: false)
class _$TemplatePreferencesImpl extends _TemplatePreferences {
  const _$TemplatePreferencesImpl(
      {this.daysPerWeek,
      this.minutesPerSession,
      @JsonKey(readValue: _readGoals)
      @RoutineGoalListConverter()
      final List<RoutineGoal> goals = const <RoutineGoal>[],
      final List<String> priorityMuscleGroups = const <String>[]})
      : _goals = goals,
        _priorityMuscleGroups = priorityMuscleGroups,
        super._();

  factory _$TemplatePreferencesImpl.fromJson(Map<String, dynamic> json) =>
      _$$TemplatePreferencesImplFromJson(json);

  /// 2..6. Null ⇒ not answered.
  @override
  final int? daysPerWeek;

  /// 30 / 45 / 60 / 75, where 75 means "75 or more" — the handoff's last
  /// option is "75 MIN O MÁS". Stored as the lower bound so a future finer
  /// scale stays comparable. Null ⇒ not answered.
  @override
  final int? minutesPerSession;

  /// Objetivos del atleta. Vacío ⇒ no respondió (NEUTRO, nunca excluye).
  ///
  /// ── Era uno solo, ahora son varios (2026-10-09, pedido del owner) ──────
  /// Antes esto era un `RoutineGoal? goal` a propósito: la idea era que "para
  /// qué entreno ahora" tenía una sola respuesta, y que lo multi-valor era
  /// cosa de la plantilla (`Routine.goals`, #635 PR#1). En uso real no se
  /// sostuvo: "salud y estética" es una respuesta legítima, y obligar a
  /// elegir una dejaba afuera a la mitad de lo que el atleta busca.
  ///
  /// ── Compatibilidad con la 1.0 de la App Store ─────────────────────────
  /// La 1.0 lee y escribe este mismo mapa y sólo conoce `goal`. Por eso:
  ///
  ///   * LEER: si `goals` falta o viene vacío y existe el `goal` legacy, vale
  ///     `[goal]` ([_readGoals]). Un atleta que respondió en la 1.0 no pierde
  ///     su respuesta al actualizar.
  ///   * ESCRIBIR: [toJson] manda `goals` Y `goal` = el primero elegido (o
  ///     null). La 1.0 sigue leyendo un valor con sentido.
  ///   * Si la 1.0 vuelve a guardar, escribe sólo `goal`. Ojo: NO reemplaza el
  ///     mapa. `UserRepository.update` persiste con `set(..., merge: true)` y
  ///     Firestore mergea los mapas anidados en profundidad, así que el
  ///     `goals` viejo SOBREVIVE junto al `goal` nuevo. La lectura lo
  ///     reconcilia con esta invariante: el cliente nuevo escribe SIEMPRE
  ///     `goal == goals.first` (o null si no hay). Si no coinciden, alguien
  ///     que sólo conoce `goal` editó después, y gana `goal` ([_readGoals]).
  ///
  /// [RoutineGoalListConverter] no es decoración: descarta los valores que no
  /// conoce en vez de tirar. Este modelo se decodifica como parte de
  /// `UserProfile`, así que un objetivo agregado por un build más nuevo, si
  /// tirara, rompería el stream del perfil entero en los clientes viejos y los
  /// mandaría a `/profile-unavailable` (#544).
// ignore: invalid_annotation_target
  final List<RoutineGoal> _goals;

  /// Objetivos del atleta. Vacío ⇒ no respondió (NEUTRO, nunca excluye).
  ///
  /// ── Era uno solo, ahora son varios (2026-10-09, pedido del owner) ──────
  /// Antes esto era un `RoutineGoal? goal` a propósito: la idea era que "para
  /// qué entreno ahora" tenía una sola respuesta, y que lo multi-valor era
  /// cosa de la plantilla (`Routine.goals`, #635 PR#1). En uso real no se
  /// sostuvo: "salud y estética" es una respuesta legítima, y obligar a
  /// elegir una dejaba afuera a la mitad de lo que el atleta busca.
  ///
  /// ── Compatibilidad con la 1.0 de la App Store ─────────────────────────
  /// La 1.0 lee y escribe este mismo mapa y sólo conoce `goal`. Por eso:
  ///
  ///   * LEER: si `goals` falta o viene vacío y existe el `goal` legacy, vale
  ///     `[goal]` ([_readGoals]). Un atleta que respondió en la 1.0 no pierde
  ///     su respuesta al actualizar.
  ///   * ESCRIBIR: [toJson] manda `goals` Y `goal` = el primero elegido (o
  ///     null). La 1.0 sigue leyendo un valor con sentido.
  ///   * Si la 1.0 vuelve a guardar, escribe sólo `goal`. Ojo: NO reemplaza el
  ///     mapa. `UserRepository.update` persiste con `set(..., merge: true)` y
  ///     Firestore mergea los mapas anidados en profundidad, así que el
  ///     `goals` viejo SOBREVIVE junto al `goal` nuevo. La lectura lo
  ///     reconcilia con esta invariante: el cliente nuevo escribe SIEMPRE
  ///     `goal == goals.first` (o null si no hay). Si no coinciden, alguien
  ///     que sólo conoce `goal` editó después, y gana `goal` ([_readGoals]).
  ///
  /// [RoutineGoalListConverter] no es decoración: descarta los valores que no
  /// conoce en vez de tirar. Este modelo se decodifica como parte de
  /// `UserProfile`, así que un objetivo agregado por un build más nuevo, si
  /// tirara, rompería el stream del perfil entero en los clientes viejos y los
  /// mandaría a `/profile-unavailable` (#544).
// ignore: invalid_annotation_target
  @override
  @JsonKey(readValue: _readGoals)
  @RoutineGoalListConverter()
  List<RoutineGoal> get goals {
    if (_goals is EqualUnmodifiableListView) return _goals;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_goals);
  }

  /// Canonical [MuscleGroup] keys (`chest`, `back`, `quads`…) — the app's one
  /// muscle vocabulary, reused rather than re-invented. Empty ⇒ no priority,
  /// which the handoff marks as explicitly optional ("Zonas a priorizar ·
  /// opcional").
  final List<String> _priorityMuscleGroups;

  /// Canonical [MuscleGroup] keys (`chest`, `back`, `quads`…) — the app's one
  /// muscle vocabulary, reused rather than re-invented. Empty ⇒ no priority,
  /// which the handoff marks as explicitly optional ("Zonas a priorizar ·
  /// opcional").
  @override
  @JsonKey()
  List<String> get priorityMuscleGroups {
    if (_priorityMuscleGroups is EqualUnmodifiableListView)
      return _priorityMuscleGroups;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_priorityMuscleGroups);
  }

  @override
  String toString() {
    return 'TemplatePreferences(daysPerWeek: $daysPerWeek, minutesPerSession: $minutesPerSession, goals: $goals, priorityMuscleGroups: $priorityMuscleGroups)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TemplatePreferencesImpl &&
            (identical(other.daysPerWeek, daysPerWeek) ||
                other.daysPerWeek == daysPerWeek) &&
            (identical(other.minutesPerSession, minutesPerSession) ||
                other.minutesPerSession == minutesPerSession) &&
            const DeepCollectionEquality().equals(other._goals, _goals) &&
            const DeepCollectionEquality()
                .equals(other._priorityMuscleGroups, _priorityMuscleGroups));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      daysPerWeek,
      minutesPerSession,
      const DeepCollectionEquality().hash(_goals),
      const DeepCollectionEquality().hash(_priorityMuscleGroups));

  /// Create a copy of TemplatePreferences
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TemplatePreferencesImplCopyWith<_$TemplatePreferencesImpl> get copyWith =>
      __$$TemplatePreferencesImplCopyWithImpl<_$TemplatePreferencesImpl>(
          this, _$identity);
}

abstract class _TemplatePreferences extends TemplatePreferences {
  const factory _TemplatePreferences(
      {final int? daysPerWeek,
      final int? minutesPerSession,
      @JsonKey(readValue: _readGoals)
      @RoutineGoalListConverter()
      final List<RoutineGoal> goals,
      final List<String> priorityMuscleGroups}) = _$TemplatePreferencesImpl;
  const _TemplatePreferences._() : super._();

  factory _TemplatePreferences.fromJson(Map<String, dynamic> json) =
      _$TemplatePreferencesImpl.fromJson;

  /// 2..6. Null ⇒ not answered.
  @override
  int? get daysPerWeek;

  /// 30 / 45 / 60 / 75, where 75 means "75 or more" — the handoff's last
  /// option is "75 MIN O MÁS". Stored as the lower bound so a future finer
  /// scale stays comparable. Null ⇒ not answered.
  @override
  int? get minutesPerSession;

  /// Objetivos del atleta. Vacío ⇒ no respondió (NEUTRO, nunca excluye).
  ///
  /// ── Era uno solo, ahora son varios (2026-10-09, pedido del owner) ──────
  /// Antes esto era un `RoutineGoal? goal` a propósito: la idea era que "para
  /// qué entreno ahora" tenía una sola respuesta, y que lo multi-valor era
  /// cosa de la plantilla (`Routine.goals`, #635 PR#1). En uso real no se
  /// sostuvo: "salud y estética" es una respuesta legítima, y obligar a
  /// elegir una dejaba afuera a la mitad de lo que el atleta busca.
  ///
  /// ── Compatibilidad con la 1.0 de la App Store ─────────────────────────
  /// La 1.0 lee y escribe este mismo mapa y sólo conoce `goal`. Por eso:
  ///
  ///   * LEER: si `goals` falta o viene vacío y existe el `goal` legacy, vale
  ///     `[goal]` ([_readGoals]). Un atleta que respondió en la 1.0 no pierde
  ///     su respuesta al actualizar.
  ///   * ESCRIBIR: [toJson] manda `goals` Y `goal` = el primero elegido (o
  ///     null). La 1.0 sigue leyendo un valor con sentido.
  ///   * Si la 1.0 vuelve a guardar, escribe sólo `goal`. Ojo: NO reemplaza el
  ///     mapa. `UserRepository.update` persiste con `set(..., merge: true)` y
  ///     Firestore mergea los mapas anidados en profundidad, así que el
  ///     `goals` viejo SOBREVIVE junto al `goal` nuevo. La lectura lo
  ///     reconcilia con esta invariante: el cliente nuevo escribe SIEMPRE
  ///     `goal == goals.first` (o null si no hay). Si no coinciden, alguien
  ///     que sólo conoce `goal` editó después, y gana `goal` ([_readGoals]).
  ///
  /// [RoutineGoalListConverter] no es decoración: descarta los valores que no
  /// conoce en vez de tirar. Este modelo se decodifica como parte de
  /// `UserProfile`, así que un objetivo agregado por un build más nuevo, si
  /// tirara, rompería el stream del perfil entero en los clientes viejos y los
  /// mandaría a `/profile-unavailable` (#544).
// ignore: invalid_annotation_target
  @override
  @JsonKey(readValue: _readGoals)
  @RoutineGoalListConverter()
  List<RoutineGoal> get goals;

  /// Canonical [MuscleGroup] keys (`chest`, `back`, `quads`…) — the app's one
  /// muscle vocabulary, reused rather than re-invented. Empty ⇒ no priority,
  /// which the handoff marks as explicitly optional ("Zonas a priorizar ·
  /// opcional").
  @override
  List<String> get priorityMuscleGroups;

  /// Create a copy of TemplatePreferences
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TemplatePreferencesImplCopyWith<_$TemplatePreferencesImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
