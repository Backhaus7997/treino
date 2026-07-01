// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'gym_brand.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$GymBrand {
  String get brandId => throw _privateConstructorUsedError;
  String get brandName => throw _privateConstructorUsedError;
  int get branchCount => throw _privateConstructorUsedError;
  String? get singleBranchGymId => throw _privateConstructorUsedError;

  /// Create a copy of GymBrand
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $GymBrandCopyWith<GymBrand> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $GymBrandCopyWith<$Res> {
  factory $GymBrandCopyWith(GymBrand value, $Res Function(GymBrand) then) =
      _$GymBrandCopyWithImpl<$Res, GymBrand>;
  @useResult
  $Res call(
      {String brandId,
      String brandName,
      int branchCount,
      String? singleBranchGymId});
}

/// @nodoc
class _$GymBrandCopyWithImpl<$Res, $Val extends GymBrand>
    implements $GymBrandCopyWith<$Res> {
  _$GymBrandCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of GymBrand
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? brandId = null,
    Object? brandName = null,
    Object? branchCount = null,
    Object? singleBranchGymId = freezed,
  }) {
    return _then(_value.copyWith(
      brandId: null == brandId
          ? _value.brandId
          : brandId // ignore: cast_nullable_to_non_nullable
              as String,
      brandName: null == brandName
          ? _value.brandName
          : brandName // ignore: cast_nullable_to_non_nullable
              as String,
      branchCount: null == branchCount
          ? _value.branchCount
          : branchCount // ignore: cast_nullable_to_non_nullable
              as int,
      singleBranchGymId: freezed == singleBranchGymId
          ? _value.singleBranchGymId
          : singleBranchGymId // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$GymBrandImplCopyWith<$Res>
    implements $GymBrandCopyWith<$Res> {
  factory _$$GymBrandImplCopyWith(
          _$GymBrandImpl value, $Res Function(_$GymBrandImpl) then) =
      __$$GymBrandImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String brandId,
      String brandName,
      int branchCount,
      String? singleBranchGymId});
}

/// @nodoc
class __$$GymBrandImplCopyWithImpl<$Res>
    extends _$GymBrandCopyWithImpl<$Res, _$GymBrandImpl>
    implements _$$GymBrandImplCopyWith<$Res> {
  __$$GymBrandImplCopyWithImpl(
      _$GymBrandImpl _value, $Res Function(_$GymBrandImpl) _then)
      : super(_value, _then);

  /// Create a copy of GymBrand
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? brandId = null,
    Object? brandName = null,
    Object? branchCount = null,
    Object? singleBranchGymId = freezed,
  }) {
    return _then(_$GymBrandImpl(
      brandId: null == brandId
          ? _value.brandId
          : brandId // ignore: cast_nullable_to_non_nullable
              as String,
      brandName: null == brandName
          ? _value.brandName
          : brandName // ignore: cast_nullable_to_non_nullable
              as String,
      branchCount: null == branchCount
          ? _value.branchCount
          : branchCount // ignore: cast_nullable_to_non_nullable
              as int,
      singleBranchGymId: freezed == singleBranchGymId
          ? _value.singleBranchGymId
          : singleBranchGymId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc

class _$GymBrandImpl extends _GymBrand {
  const _$GymBrandImpl(
      {required this.brandId,
      required this.brandName,
      required this.branchCount,
      this.singleBranchGymId})
      : super._();

  @override
  final String brandId;
  @override
  final String brandName;
  @override
  final int branchCount;
  @override
  final String? singleBranchGymId;

  @override
  String toString() {
    return 'GymBrand(brandId: $brandId, brandName: $brandName, branchCount: $branchCount, singleBranchGymId: $singleBranchGymId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$GymBrandImpl &&
            (identical(other.brandId, brandId) || other.brandId == brandId) &&
            (identical(other.brandName, brandName) ||
                other.brandName == brandName) &&
            (identical(other.branchCount, branchCount) ||
                other.branchCount == branchCount) &&
            (identical(other.singleBranchGymId, singleBranchGymId) ||
                other.singleBranchGymId == singleBranchGymId));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType, brandId, brandName, branchCount, singleBranchGymId);

  /// Create a copy of GymBrand
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$GymBrandImplCopyWith<_$GymBrandImpl> get copyWith =>
      __$$GymBrandImplCopyWithImpl<_$GymBrandImpl>(this, _$identity);
}

abstract class _GymBrand extends GymBrand {
  const factory _GymBrand(
      {required final String brandId,
      required final String brandName,
      required final int branchCount,
      final String? singleBranchGymId}) = _$GymBrandImpl;
  const _GymBrand._() : super._();

  @override
  String get brandId;
  @override
  String get brandName;
  @override
  int get branchCount;
  @override
  String? get singleBranchGymId;

  /// Create a copy of GymBrand
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$GymBrandImplCopyWith<_$GymBrandImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
