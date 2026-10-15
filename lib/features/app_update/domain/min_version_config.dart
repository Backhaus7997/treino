import 'app_version.dart';

/// Plataformas móviles que el gate sabe evaluar. Web y relojes no entran.
enum AppUpdatePlatform { ios, android }

/// Contenido del documento público `app_config/min_version`.
///
/// ```json
/// {
///   "minVersion": { "ios": "1.4.0", "android": "1.4.0" },
///   "storeUrl":   { "ios": "https://apps.apple.com/...", "android": "https://play.google.com/..." }
/// }
/// ```
///
/// `storeUrl` es opcional (hay un fallback en el código). Cada plataforma se
/// configura por separado: bajar solo `android` no toca a iOS.
class MinVersionConfig {
  const MinVersionConfig({required this.minVersion, required this.storeUrl});

  final Map<AppUpdatePlatform, String> minVersion;
  final Map<AppUpdatePlatform, String> storeUrl;

  /// `null` si el documento no existe o no es un mapa. Entradas individuales
  /// malformadas (no-string, versión no parseable, URL no http/https) se
  /// descartan solas: una plataforma rota no invalida a la otra, y una
  /// plataforma sin mínimo válido simplemente no se gatea.
  static MinVersionConfig? fromMap(Map<String, dynamic>? data) {
    if (data == null) return null;
    return MinVersionConfig(
      minVersion: _porPlataforma(data['minVersion'], (v) {
        return parseAppVersion(v) == null ? null : v.trim();
      }),
      storeUrl: _porPlataforma(data['storeUrl'], (v) {
        final uri = Uri.tryParse(v.trim());
        final ok = uri != null &&
            (uri.scheme == 'https' || uri.scheme == 'http') &&
            uri.host.isNotEmpty;
        return ok ? v.trim() : null;
      }),
    );
  }

  static Map<AppUpdatePlatform, String> _porPlataforma(
    Object? raw,
    String? Function(String) validar,
  ) {
    final out = <AppUpdatePlatform, String>{};
    if (raw is! Map) return out;
    for (final p in AppUpdatePlatform.values) {
      final v = raw[p.name];
      if (v is! String) continue;
      final ok = validar(v);
      if (ok != null) out[p] = ok;
    }
    return out;
  }
}

/// Fallback si el documento no trae `storeUrl` para la plataforma.
///
/// Android: el `applicationId` es `com.treino.app`. iOS: el Apple ID de
/// "TREINO Fitness" en App Store Connect es `6781307745` (docs/roadmap.md).
const Map<AppUpdatePlatform, String> kStoreUrlFallback = {
  AppUpdatePlatform.android:
      'https://play.google.com/store/apps/details?id=com.treino.app',
  AppUpdatePlatform.ios: 'https://apps.apple.com/app/id6781307745',
};

/// Resultado de evaluar el gate: hay que actualizar, y a dónde mandar.
class UpdateRequirement {
  const UpdateRequirement({required this.storeUrl});
  final String storeUrl;

  /// `null` ⇒ no bloquear. Falla abierto ante CUALQUIER dato faltante: sin
  /// plataforma, sin config, sin mínimo para la plataforma, o versión
  /// instalada ilegible.
  static UpdateRequirement? evaluar({
    required AppUpdatePlatform? platform,
    required String? installedVersion,
    required MinVersionConfig? config,
  }) {
    if (platform == null || config == null) return null;
    final minimo = config.minVersion[platform];
    if (!isOlderThan(installedVersion, minimo)) return null;
    return UpdateRequirement(
      storeUrl: config.storeUrl[platform] ?? kStoreUrlFallback[platform]!,
    );
  }
}
