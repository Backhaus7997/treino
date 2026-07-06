// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'nutrition_plan.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$FoodOptionImpl _$$FoodOptionImplFromJson(Map<String, dynamic> json) =>
    _$FoodOptionImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      quantity: json['quantity'] as String?,
      unit: json['unit'] as String?,
      notes: json['notes'] as String?,
    );

Map<String, dynamic> _$$FoodOptionImplToJson(_$FoodOptionImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'quantity': instance.quantity,
      'unit': instance.unit,
      'notes': instance.notes,
    };

_$FoodGroupImpl _$$FoodGroupImplFromJson(Map<String, dynamic> json) =>
    _$FoodGroupImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      selectionMode: $enumDecode(_$SelectionModeEnumMap, json['selectionMode']),
      options: (json['options'] as List<dynamic>)
          .map((e) => FoodOption.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$$FoodGroupImplToJson(_$FoodGroupImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'selectionMode': _$SelectionModeEnumMap[instance.selectionMode]!,
      'options': instance.options.map((e) => e.toJson()).toList(),
    };

const _$SelectionModeEnumMap = {
  SelectionMode.chooseOne: 'chooseOne',
  SelectionMode.all: 'all',
};

_$MealImpl _$$MealImplFromJson(Map<String, dynamic> json) => _$MealImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      time: json['time'] as String?,
      groups: (json['groups'] as List<dynamic>)
          .map((e) => FoodGroup.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$$MealImplToJson(_$MealImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'time': instance.time,
      'groups': instance.groups.map((e) => e.toJson()).toList(),
    };

_$NutritionPlanImpl _$$NutritionPlanImplFromJson(Map<String, dynamic> json) =>
    _$NutritionPlanImpl(
      id: json['id'] as String,
      trainerId: json['trainerId'] as String,
      athleteId: json['athleteId'] as String,
      title: json['title'] as String,
      meals: (json['meals'] as List<dynamic>)
          .map((e) => Meal.fromJson(e as Map<String, dynamic>))
          .toList(),
      updatedAt:
          const TimestampConverter().fromJson(json['updatedAt'] as Timestamp),
    );

Map<String, dynamic> _$$NutritionPlanImplToJson(_$NutritionPlanImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'trainerId': instance.trainerId,
      'athleteId': instance.athleteId,
      'title': instance.title,
      'meals': instance.meals.map((e) => e.toJson()).toList(),
      'updatedAt': const TimestampConverter().toJson(instance.updatedAt),
    };
