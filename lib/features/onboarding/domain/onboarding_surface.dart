/// Superficies que tienen tour de onboarding PROPIO (issue #627).
///
/// ⚠️  Una entrada por superficie, NO un flag global. Un PF que ya vio el tour
/// de mobile tiene que ver igual el del Coach Hub web — es justamente el que
/// más le hace falta. Con un flag único compartido, el segundo tour no se
/// mostraría nunca.
///
/// [version] es la versión ACTUAL del contenido de ese tour. El flag persistido
/// guarda la versión que el usuario efectivamente vio; el tour se considera
/// pendiente cuando `vista < version`. Un rediseño futuro sube este número y
/// el tour se re-muestra solo, sin migración manual de datos.
enum OnboardingSurface {
  /// Tour del ALUMNO en la app mobile (slice 1 — esta).
  athleteMobile(key: 'athleteMobile', version: 1),

  /// Tour del PF en la app mobile (slice 2).
  trainerMobile(key: 'trainerMobile', version: 1),

  /// Tour del PF en el Coach Hub web (slice 3).
  trainerWeb(key: 'trainerWeb', version: 1);

  const OnboardingSurface({required this.key, required this.version});

  /// Clave dentro del mapa persistido `users/{uid}.onboardingSeen`.
  ///
  /// Es el contrato de datos: NO renombrarla sin una migración. El nombre del
  /// valor del enum puede cambiar libremente, esta string no.
  final String key;

  /// Versión del contenido del tour de esta superficie. Subila cuando el copy
  /// o las pantallas cambien lo suficiente como para querer re-mostrarlo.
  final int version;

  /// Resuelve una superficie por su clave persistida. `null` para claves
  /// desconocidas (docs escritos por una versión más nueva de la app).
  static OnboardingSurface? fromKey(String key) {
    for (final surface in OnboardingSurface.values) {
      if (surface.key == key) return surface;
    }
    return null;
  }
}
