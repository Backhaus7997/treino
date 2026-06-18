import 'package:json_annotation/json_annotation.dart';

/// Tipo de medio adjunto a un [Message]. Sigue el mismo patrón de serialización
/// que [Gender] y [UserRole] (REQ-CHATMEDIA-002).
enum MediaType {
  @JsonValue('image')
  image,
  @JsonValue('video')
  video,
}

extension MediaTypeX on MediaType {
  static const _wireMap = {
    'image': MediaType.image,
    'video': MediaType.video,
  };

  static MediaType fromJson(String value) {
    final mediaType = _wireMap[value];
    if (mediaType == null) {
      throw ArgumentError.value(value, 'value', 'Unknown MediaType wire value');
    }
    return mediaType;
  }

  String toJson() => switch (this) {
        MediaType.image => 'image',
        MediaType.video => 'video',
      };
}
