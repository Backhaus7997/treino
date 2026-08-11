import 'package:json_annotation/json_annotation.dart';

/// Tier de visibilidad de un post.
///
/// **El símbolo Dart y el valor de wire NO coinciden a propósito** (LD-05):
/// `followers` viaja a Firestore como `'friends'`. El change `follow-model`
/// renombró el concepto de "amigos" a "seguidores" en toda la UI, pero cambiar
/// también el valor almacenado habría convertido un rename cosmético en una
/// migración de datos sobre TODOS los posts existentes — y habría roto las
/// rules, que matchean `resource.data.privacy == 'friends'`.
///
/// El wire value es deuda de nombre, no de comportamiento. Si algún día se
/// migra, es un change aparte con su propio backfill. No "prolijar" el
/// `@JsonValue` — hay un test que lo ancla (SCENARIO-810).
enum PostPrivacy {
  @JsonValue('friends')
  followers,
  @JsonValue('gym')
  gym,
  @JsonValue('public')
  public,
}

extension PostPrivacyX on PostPrivacy {
  static const _wireMap = {
    'friends': PostPrivacy.followers,
    'gym': PostPrivacy.gym,
    'public': PostPrivacy.public,
  };

  static PostPrivacy fromJson(String value) {
    final privacy = _wireMap[value];
    if (privacy == null) {
      throw ArgumentError.value(
        value,
        'value',
        'Unknown PostPrivacy wire value',
      );
    }
    return privacy;
  }

  String toJson() => switch (this) {
        // ← el wire value NO acompaña al rename. Ver el doc del enum (LD-05).
        PostPrivacy.followers => 'friends',
        PostPrivacy.gym => 'gym',
        PostPrivacy.public => 'public',
      };
}
