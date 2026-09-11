import 'package:json_annotation/json_annotation.dart';

/// Qué tipo de contenido se está reportando.
enum ReportTargetKind {
  @JsonValue('post')
  post,

  @JsonValue('message')
  message,

  @JsonValue('review')
  review,

  @JsonValue('profile')
  profile,
}

extension ReportTargetKindX on ReportTargetKind {
  static const _wireMap = {
    'post': ReportTargetKind.post,
    'message': ReportTargetKind.message,
    'review': ReportTargetKind.review,
    'profile': ReportTargetKind.profile,
  };

  /// Tira [ArgumentError] ante un valor desconocido en vez de devolver un
  /// default — mismo criterio que `FollowStatusX.fromJson`. Un reporte con un
  /// `targetKind` corrupto no debería resolver en silencio a un tipo
  /// arbitrario.
  static ReportTargetKind fromJson(String value) {
    final kind = _wireMap[value];
    if (kind == null) {
      throw ArgumentError.value(
        value,
        'value',
        'Unknown ReportTargetKind wire value',
      );
    }
    return kind;
  }

  String toJson() => switch (this) {
        ReportTargetKind.post => 'post',
        ReportTargetKind.message => 'message',
        ReportTargetKind.review => 'review',
        ReportTargetKind.profile => 'profile',
      };
}
