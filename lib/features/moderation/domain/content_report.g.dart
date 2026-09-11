// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'content_report.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ContentReportImpl _$$ContentReportImplFromJson(Map<String, dynamic> json) =>
    _$ContentReportImpl(
      id: json['id'] as String,
      reporterUid: json['reporterUid'] as String,
      targetKind: $enumDecode(_$ReportTargetKindEnumMap, json['targetKind']),
      targetId: json['targetId'] as String,
      targetOwnerUid: json['targetOwnerUid'] as String,
      reason: $enumDecode(_$ReportReasonEnumMap, json['reason']),
      detail: json['detail'] as String?,
      createdAt:
          const TimestampConverter().fromJson(json['createdAt'] as Timestamp),
    );

Map<String, dynamic> _$$ContentReportImplToJson(_$ContentReportImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'reporterUid': instance.reporterUid,
      'targetKind': _$ReportTargetKindEnumMap[instance.targetKind]!,
      'targetId': instance.targetId,
      'targetOwnerUid': instance.targetOwnerUid,
      'reason': _$ReportReasonEnumMap[instance.reason]!,
      'detail': instance.detail,
      'createdAt': const TimestampConverter().toJson(instance.createdAt),
    };

const _$ReportTargetKindEnumMap = {
  ReportTargetKind.post: 'post',
  ReportTargetKind.message: 'message',
  ReportTargetKind.review: 'review',
  ReportTargetKind.profile: 'profile',
};

const _$ReportReasonEnumMap = {
  ReportReason.harassment: 'harassment',
  ReportReason.sexualContent: 'sexualContent',
  ReportReason.violenceOrSelfHarm: 'violenceOrSelfHarm',
  ReportReason.dangerousHealthAdvice: 'dangerousHealthAdvice',
  ReportReason.impersonation: 'impersonation',
  ReportReason.spam: 'spam',
  ReportReason.thirdPartyData: 'thirdPartyData',
  ReportReason.intellectualProperty: 'intellectualProperty',
  ReportReason.other: 'other',
};
