import 'package:json_annotation/json_annotation.dart';

enum SessionStatus {
  @JsonValue('active')
  active,
  @JsonValue('finished')
  finished,
}

extension SessionStatusX on SessionStatus {
  static const _wireMap = {
    'active': SessionStatus.active,
    'finished': SessionStatus.finished,
  };

  static SessionStatus fromJson(String value) {
    final status = _wireMap[value];
    if (status == null) {
      throw ArgumentError.value(
          value, 'value', 'Unknown SessionStatus wire value');
    }
    return status;
  }

  String toJson() => switch (this) {
        SessionStatus.active => 'active',
        SessionStatus.finished => 'finished',
      };
}
