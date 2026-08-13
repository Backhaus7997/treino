import 'package:freezed_annotation/freezed_annotation.dart';

import 'onboarding_surface.dart';

/// Mapa `superficie -> versión del tour ya vista` (issue #627).
///
/// Se persiste en Firestore dentro de `users/{uid}.onboardingSeen` — NO en
/// SharedPreferences — para que el "ya lo vi" sea cross-device.
///
/// Forma en el doc:
/// ```json
/// { "onboardingSeen": { "athleteMobile": 1, "trainerWeb": 2 } }
/// ```
///
/// Ausencia de clave == versión 0 == nunca visto. Eso incluye a las cuentas
/// que existían ANTES de este feature: la primera vez que abren la app ven el
/// tour una vez. Es intencional, y es la misma mecánica que hace que un bump
/// de [OnboardingSurface.version] re-muestre el tour sin migrar datos.
class OnboardingSeen {
  const OnboardingSeen(this._versions);

  /// Estado inicial: ninguna superficie vista. Usado como `@Default` del campo
  /// en `UserProfile`, así que TIENE que ser const.
  static const OnboardingSeen empty = OnboardingSeen(<String, int>{});

  final Map<String, int> _versions;

  /// Versión del tour de [surface] que el usuario ya vio. 0 == nunca.
  int versionFor(OnboardingSurface surface) => _versions[surface.key] ?? 0;

  /// `true` cuando el usuario ya vio el tour de [surface] en su versión ACTUAL.
  bool hasSeen(OnboardingSurface surface) =>
      versionFor(surface) >= surface.version;

  /// `true` cuando todavía le falta ver (o re-ver, tras un bump de versión) el
  /// tour de [surface]. Es el predicado que consume el gate del router.
  bool isPending(OnboardingSurface surface) => !hasSeen(surface);

  /// Copia con [surface] marcada como vista en su versión actual. Las demás
  /// superficies quedan intactas.
  OnboardingSeen markSeen(OnboardingSurface surface) => OnboardingSeen({
        ..._versions,
        surface.key: surface.version,
      });

  /// Copia con [surface] vuelta a "nunca visto" — lo que necesita el entry
  /// point de "re-ver el tour" (Perfil en mobile, `ajustes` en el Hub).
  ///
  /// Escribe `0` en vez de borrar la clave a propósito: el write al doc usa
  /// `SetOptions(merge: true)`, que hace merge PROFUNDO de los mapas y por lo
  /// tanto no puede eliminar una clave. Un 0 explícito sí sobrescribe.
  OnboardingSeen reset(OnboardingSurface surface) => OnboardingSeen({
        ..._versions,
        surface.key: 0,
      });

  Map<String, Object?> toJson() => Map<String, Object?>.from(_versions);

  /// Tolerante a propósito con lo que venga del backend:
  /// - claves desconocidas se preservan tal cual (un cliente viejo no debe
  ///   borrar el flag de una superficie que todavía no conoce);
  /// - valores no numéricos o negativos se normalizan a 0 (== no visto), que
  ///   es el lado seguro: mostrar el tour de más nunca rompe nada, tragárselo
  ///   deja al usuario sin onboarding para siempre.
  factory OnboardingSeen.fromJson(Map<String, Object?> json) {
    final parsed = <String, int>{};
    json.forEach((key, value) {
      final version = value is num ? value.toInt() : 0;
      parsed[key] = version < 0 ? 0 : version;
    });
    return OnboardingSeen(parsed);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! OnboardingSeen) return false;
    if (other._versions.length != _versions.length) return false;
    for (final entry in _versions.entries) {
      if (other._versions[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
        _versions.entries.map((e) => Object.hash(e.key, e.value)),
      );

  @override
  String toString() => 'OnboardingSeen($_versions)';
}

/// Converter para el campo `onboardingSeen` de `UserProfile`.
///
/// Mismo idioma que `@TimestampConverter()`. Existe en vez de tipar el campo
/// como `Map<String, int>` porque json_serializable generaría un `e as int`
/// duro sobre lo que devuelva Firestore, y Firestore es notoriamente flojo con
/// los tipos numéricos: un `1` que vuelve como `double` reventaría el parseo
/// del perfil entero. [OnboardingSeen.fromJson] normaliza en su lugar.
class OnboardingSeenConverter
    implements JsonConverter<OnboardingSeen, Map<String, Object?>> {
  const OnboardingSeenConverter();

  @override
  OnboardingSeen fromJson(Map<String, Object?> json) =>
      OnboardingSeen.fromJson(json);

  @override
  Map<String, Object?> toJson(OnboardingSeen value) => value.toJson();
}
