// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'template_rating.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$TemplateRatingImpl _$$TemplateRatingImplFromJson(Map<String, dynamic> json) =>
    _$TemplateRatingImpl(
      userId: json['userId'] as String,
      rating: (json['rating'] as num).toInt(),
      comment: json['comment'] as String?,
      createdAt:
          const TimestampConverter().fromJson(json['createdAt'] as Timestamp),
      updatedAt:
          const TimestampConverter().fromJson(json['updatedAt'] as Timestamp),
    );

Map<String, dynamic> _$$TemplateRatingImplToJson(
        _$TemplateRatingImpl instance) =>
    <String, dynamic>{
      'userId': instance.userId,
      'rating': instance.rating,
      'comment': instance.comment,
      'createdAt': const TimestampConverter().toJson(instance.createdAt),
      'updatedAt': const TimestampConverter().toJson(instance.updatedAt),
    };
