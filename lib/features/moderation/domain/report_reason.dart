import 'package:json_annotation/json_annotation.dart';

/// Taxonomía de motivos de reporte. Nueve valores cerrados — agregar uno
/// nuevo es una decisión de producto, no un `String` libre.
enum ReportReason {
  @JsonValue('harassment')
  harassment,

  @JsonValue('sexualContent')
  sexualContent,

  @JsonValue('violenceOrSelfHarm')
  violenceOrSelfHarm,

  @JsonValue('dangerousHealthAdvice')
  dangerousHealthAdvice,

  @JsonValue('impersonation')
  impersonation,

  @JsonValue('spam')
  spam,

  @JsonValue('thirdPartyData')
  thirdPartyData,

  @JsonValue('intellectualProperty')
  intellectualProperty,

  @JsonValue('other')
  other,
}

extension ReportReasonX on ReportReason {
  static const _wireMap = {
    'harassment': ReportReason.harassment,
    'sexualContent': ReportReason.sexualContent,
    'violenceOrSelfHarm': ReportReason.violenceOrSelfHarm,
    'dangerousHealthAdvice': ReportReason.dangerousHealthAdvice,
    'impersonation': ReportReason.impersonation,
    'spam': ReportReason.spam,
    'thirdPartyData': ReportReason.thirdPartyData,
    'intellectualProperty': ReportReason.intellectualProperty,
    'other': ReportReason.other,
  };

  /// Tira [ArgumentError] ante un valor desconocido — mismo criterio que
  /// `FollowStatusX.fromJson`.
  static ReportReason fromJson(String value) {
    final reason = _wireMap[value];
    if (reason == null) {
      throw ArgumentError.value(
        value,
        'value',
        'Unknown ReportReason wire value',
      );
    }
    return reason;
  }

  String toJson() => switch (this) {
        ReportReason.harassment => 'harassment',
        ReportReason.sexualContent => 'sexualContent',
        ReportReason.violenceOrSelfHarm => 'violenceOrSelfHarm',
        ReportReason.dangerousHealthAdvice => 'dangerousHealthAdvice',
        ReportReason.impersonation => 'impersonation',
        ReportReason.spam => 'spam',
        ReportReason.thirdPartyData => 'thirdPartyData',
        ReportReason.intellectualProperty => 'intellectualProperty',
        ReportReason.other => 'other',
      };
}
