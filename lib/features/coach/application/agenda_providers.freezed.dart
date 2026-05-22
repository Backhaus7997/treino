// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'agenda_providers.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$OverridesKey {
  String get trainerId => throw _privateConstructorUsedError;
  DateTime get fromDate => throw _privateConstructorUsedError;
  DateTime get toDate => throw _privateConstructorUsedError;

  /// Create a copy of OverridesKey
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $OverridesKeyCopyWith<OverridesKey> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OverridesKeyCopyWith<$Res> {
  factory $OverridesKeyCopyWith(
          OverridesKey value, $Res Function(OverridesKey) then) =
      _$OverridesKeyCopyWithImpl<$Res, OverridesKey>;
  @useResult
  $Res call({String trainerId, DateTime fromDate, DateTime toDate});
}

/// @nodoc
class _$OverridesKeyCopyWithImpl<$Res, $Val extends OverridesKey>
    implements $OverridesKeyCopyWith<$Res> {
  _$OverridesKeyCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of OverridesKey
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? trainerId = null,
    Object? fromDate = null,
    Object? toDate = null,
  }) {
    return _then(_value.copyWith(
      trainerId: null == trainerId
          ? _value.trainerId
          : trainerId // ignore: cast_nullable_to_non_nullable
              as String,
      fromDate: null == fromDate
          ? _value.fromDate
          : fromDate // ignore: cast_nullable_to_non_nullable
              as DateTime,
      toDate: null == toDate
          ? _value.toDate
          : toDate // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$OverridesKeyImplCopyWith<$Res>
    implements $OverridesKeyCopyWith<$Res> {
  factory _$$OverridesKeyImplCopyWith(
          _$OverridesKeyImpl value, $Res Function(_$OverridesKeyImpl) then) =
      __$$OverridesKeyImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String trainerId, DateTime fromDate, DateTime toDate});
}

/// @nodoc
class __$$OverridesKeyImplCopyWithImpl<$Res>
    extends _$OverridesKeyCopyWithImpl<$Res, _$OverridesKeyImpl>
    implements _$$OverridesKeyImplCopyWith<$Res> {
  __$$OverridesKeyImplCopyWithImpl(
      _$OverridesKeyImpl _value, $Res Function(_$OverridesKeyImpl) _then)
      : super(_value, _then);

  /// Create a copy of OverridesKey
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? trainerId = null,
    Object? fromDate = null,
    Object? toDate = null,
  }) {
    return _then(_$OverridesKeyImpl(
      trainerId: null == trainerId
          ? _value.trainerId
          : trainerId // ignore: cast_nullable_to_non_nullable
              as String,
      fromDate: null == fromDate
          ? _value.fromDate
          : fromDate // ignore: cast_nullable_to_non_nullable
              as DateTime,
      toDate: null == toDate
          ? _value.toDate
          : toDate // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc

class _$OverridesKeyImpl implements _OverridesKey {
  const _$OverridesKeyImpl(
      {required this.trainerId, required this.fromDate, required this.toDate});

  @override
  final String trainerId;
  @override
  final DateTime fromDate;
  @override
  final DateTime toDate;

  @override
  String toString() {
    return 'OverridesKey(trainerId: $trainerId, fromDate: $fromDate, toDate: $toDate)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OverridesKeyImpl &&
            (identical(other.trainerId, trainerId) ||
                other.trainerId == trainerId) &&
            (identical(other.fromDate, fromDate) ||
                other.fromDate == fromDate) &&
            (identical(other.toDate, toDate) || other.toDate == toDate));
  }

  @override
  int get hashCode => Object.hash(runtimeType, trainerId, fromDate, toDate);

  /// Create a copy of OverridesKey
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OverridesKeyImplCopyWith<_$OverridesKeyImpl> get copyWith =>
      __$$OverridesKeyImplCopyWithImpl<_$OverridesKeyImpl>(this, _$identity);
}

abstract class _OverridesKey implements OverridesKey {
  const factory _OverridesKey(
      {required final String trainerId,
      required final DateTime fromDate,
      required final DateTime toDate}) = _$OverridesKeyImpl;

  @override
  String get trainerId;
  @override
  DateTime get fromDate;
  @override
  DateTime get toDate;

  /// Create a copy of OverridesKey
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OverridesKeyImplCopyWith<_$OverridesKeyImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$TrainerAppointmentsKey {
  String get trainerId => throw _privateConstructorUsedError;
  DateTime get fromDate => throw _privateConstructorUsedError;
  DateTime get toDate => throw _privateConstructorUsedError;

  /// Create a copy of TrainerAppointmentsKey
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $TrainerAppointmentsKeyCopyWith<TrainerAppointmentsKey> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TrainerAppointmentsKeyCopyWith<$Res> {
  factory $TrainerAppointmentsKeyCopyWith(TrainerAppointmentsKey value,
          $Res Function(TrainerAppointmentsKey) then) =
      _$TrainerAppointmentsKeyCopyWithImpl<$Res, TrainerAppointmentsKey>;
  @useResult
  $Res call({String trainerId, DateTime fromDate, DateTime toDate});
}

/// @nodoc
class _$TrainerAppointmentsKeyCopyWithImpl<$Res,
        $Val extends TrainerAppointmentsKey>
    implements $TrainerAppointmentsKeyCopyWith<$Res> {
  _$TrainerAppointmentsKeyCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of TrainerAppointmentsKey
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? trainerId = null,
    Object? fromDate = null,
    Object? toDate = null,
  }) {
    return _then(_value.copyWith(
      trainerId: null == trainerId
          ? _value.trainerId
          : trainerId // ignore: cast_nullable_to_non_nullable
              as String,
      fromDate: null == fromDate
          ? _value.fromDate
          : fromDate // ignore: cast_nullable_to_non_nullable
              as DateTime,
      toDate: null == toDate
          ? _value.toDate
          : toDate // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$TrainerAppointmentsKeyImplCopyWith<$Res>
    implements $TrainerAppointmentsKeyCopyWith<$Res> {
  factory _$$TrainerAppointmentsKeyImplCopyWith(
          _$TrainerAppointmentsKeyImpl value,
          $Res Function(_$TrainerAppointmentsKeyImpl) then) =
      __$$TrainerAppointmentsKeyImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String trainerId, DateTime fromDate, DateTime toDate});
}

/// @nodoc
class __$$TrainerAppointmentsKeyImplCopyWithImpl<$Res>
    extends _$TrainerAppointmentsKeyCopyWithImpl<$Res,
        _$TrainerAppointmentsKeyImpl>
    implements _$$TrainerAppointmentsKeyImplCopyWith<$Res> {
  __$$TrainerAppointmentsKeyImplCopyWithImpl(
      _$TrainerAppointmentsKeyImpl _value,
      $Res Function(_$TrainerAppointmentsKeyImpl) _then)
      : super(_value, _then);

  /// Create a copy of TrainerAppointmentsKey
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? trainerId = null,
    Object? fromDate = null,
    Object? toDate = null,
  }) {
    return _then(_$TrainerAppointmentsKeyImpl(
      trainerId: null == trainerId
          ? _value.trainerId
          : trainerId // ignore: cast_nullable_to_non_nullable
              as String,
      fromDate: null == fromDate
          ? _value.fromDate
          : fromDate // ignore: cast_nullable_to_non_nullable
              as DateTime,
      toDate: null == toDate
          ? _value.toDate
          : toDate // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc

class _$TrainerAppointmentsKeyImpl implements _TrainerAppointmentsKey {
  const _$TrainerAppointmentsKeyImpl(
      {required this.trainerId, required this.fromDate, required this.toDate});

  @override
  final String trainerId;
  @override
  final DateTime fromDate;
  @override
  final DateTime toDate;

  @override
  String toString() {
    return 'TrainerAppointmentsKey(trainerId: $trainerId, fromDate: $fromDate, toDate: $toDate)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TrainerAppointmentsKeyImpl &&
            (identical(other.trainerId, trainerId) ||
                other.trainerId == trainerId) &&
            (identical(other.fromDate, fromDate) ||
                other.fromDate == fromDate) &&
            (identical(other.toDate, toDate) || other.toDate == toDate));
  }

  @override
  int get hashCode => Object.hash(runtimeType, trainerId, fromDate, toDate);

  /// Create a copy of TrainerAppointmentsKey
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TrainerAppointmentsKeyImplCopyWith<_$TrainerAppointmentsKeyImpl>
      get copyWith => __$$TrainerAppointmentsKeyImplCopyWithImpl<
          _$TrainerAppointmentsKeyImpl>(this, _$identity);
}

abstract class _TrainerAppointmentsKey implements TrainerAppointmentsKey {
  const factory _TrainerAppointmentsKey(
      {required final String trainerId,
      required final DateTime fromDate,
      required final DateTime toDate}) = _$TrainerAppointmentsKeyImpl;

  @override
  String get trainerId;
  @override
  DateTime get fromDate;
  @override
  DateTime get toDate;

  /// Create a copy of TrainerAppointmentsKey
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TrainerAppointmentsKeyImplCopyWith<_$TrainerAppointmentsKeyImpl>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$FreeSlotsKey {
  String get trainerId => throw _privateConstructorUsedError;
  DateTime get forDate => throw _privateConstructorUsedError;
  DateTime get fromDate => throw _privateConstructorUsedError;
  DateTime get toDate => throw _privateConstructorUsedError;

  /// Create a copy of FreeSlotsKey
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $FreeSlotsKeyCopyWith<FreeSlotsKey> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $FreeSlotsKeyCopyWith<$Res> {
  factory $FreeSlotsKeyCopyWith(
          FreeSlotsKey value, $Res Function(FreeSlotsKey) then) =
      _$FreeSlotsKeyCopyWithImpl<$Res, FreeSlotsKey>;
  @useResult
  $Res call(
      {String trainerId, DateTime forDate, DateTime fromDate, DateTime toDate});
}

/// @nodoc
class _$FreeSlotsKeyCopyWithImpl<$Res, $Val extends FreeSlotsKey>
    implements $FreeSlotsKeyCopyWith<$Res> {
  _$FreeSlotsKeyCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of FreeSlotsKey
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? trainerId = null,
    Object? forDate = null,
    Object? fromDate = null,
    Object? toDate = null,
  }) {
    return _then(_value.copyWith(
      trainerId: null == trainerId
          ? _value.trainerId
          : trainerId // ignore: cast_nullable_to_non_nullable
              as String,
      forDate: null == forDate
          ? _value.forDate
          : forDate // ignore: cast_nullable_to_non_nullable
              as DateTime,
      fromDate: null == fromDate
          ? _value.fromDate
          : fromDate // ignore: cast_nullable_to_non_nullable
              as DateTime,
      toDate: null == toDate
          ? _value.toDate
          : toDate // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$FreeSlotsKeyImplCopyWith<$Res>
    implements $FreeSlotsKeyCopyWith<$Res> {
  factory _$$FreeSlotsKeyImplCopyWith(
          _$FreeSlotsKeyImpl value, $Res Function(_$FreeSlotsKeyImpl) then) =
      __$$FreeSlotsKeyImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String trainerId, DateTime forDate, DateTime fromDate, DateTime toDate});
}

/// @nodoc
class __$$FreeSlotsKeyImplCopyWithImpl<$Res>
    extends _$FreeSlotsKeyCopyWithImpl<$Res, _$FreeSlotsKeyImpl>
    implements _$$FreeSlotsKeyImplCopyWith<$Res> {
  __$$FreeSlotsKeyImplCopyWithImpl(
      _$FreeSlotsKeyImpl _value, $Res Function(_$FreeSlotsKeyImpl) _then)
      : super(_value, _then);

  /// Create a copy of FreeSlotsKey
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? trainerId = null,
    Object? forDate = null,
    Object? fromDate = null,
    Object? toDate = null,
  }) {
    return _then(_$FreeSlotsKeyImpl(
      trainerId: null == trainerId
          ? _value.trainerId
          : trainerId // ignore: cast_nullable_to_non_nullable
              as String,
      forDate: null == forDate
          ? _value.forDate
          : forDate // ignore: cast_nullable_to_non_nullable
              as DateTime,
      fromDate: null == fromDate
          ? _value.fromDate
          : fromDate // ignore: cast_nullable_to_non_nullable
              as DateTime,
      toDate: null == toDate
          ? _value.toDate
          : toDate // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc

class _$FreeSlotsKeyImpl implements _FreeSlotsKey {
  const _$FreeSlotsKeyImpl(
      {required this.trainerId,
      required this.forDate,
      required this.fromDate,
      required this.toDate});

  @override
  final String trainerId;
  @override
  final DateTime forDate;
  @override
  final DateTime fromDate;
  @override
  final DateTime toDate;

  @override
  String toString() {
    return 'FreeSlotsKey(trainerId: $trainerId, forDate: $forDate, fromDate: $fromDate, toDate: $toDate)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FreeSlotsKeyImpl &&
            (identical(other.trainerId, trainerId) ||
                other.trainerId == trainerId) &&
            (identical(other.forDate, forDate) || other.forDate == forDate) &&
            (identical(other.fromDate, fromDate) ||
                other.fromDate == fromDate) &&
            (identical(other.toDate, toDate) || other.toDate == toDate));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, trainerId, forDate, fromDate, toDate);

  /// Create a copy of FreeSlotsKey
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$FreeSlotsKeyImplCopyWith<_$FreeSlotsKeyImpl> get copyWith =>
      __$$FreeSlotsKeyImplCopyWithImpl<_$FreeSlotsKeyImpl>(this, _$identity);
}

abstract class _FreeSlotsKey implements FreeSlotsKey {
  const factory _FreeSlotsKey(
      {required final String trainerId,
      required final DateTime forDate,
      required final DateTime fromDate,
      required final DateTime toDate}) = _$FreeSlotsKeyImpl;

  @override
  String get trainerId;
  @override
  DateTime get forDate;
  @override
  DateTime get fromDate;
  @override
  DateTime get toDate;

  /// Create a copy of FreeSlotsKey
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$FreeSlotsKeyImplCopyWith<_$FreeSlotsKeyImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
