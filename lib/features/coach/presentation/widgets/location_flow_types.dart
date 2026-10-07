/// Para qué se pide la ubicación: define los textos del mensaje previo y de
/// los avisos de Ajustes, que tienen que hablar de lo que el usuario está
/// haciendo (y ofrecer una salida que exista en ESA pantalla).
enum LocationPurpose {
  /// Descubrir entrenadores cerca (Coach, chip «Distancia»).
  trainers,

  /// Lista de gimnasios cercanos del selector de gimnasio.
  nearbyGyms,

  /// «Detectar» del editor de lugares del PF.
  trainerDetect,
}

/// Resultado de [presentLocationPermissionFlow].
enum LocationFlowOutcome {
  /// El permiso está otorgado: el caller ya puede adquirir la posición.
  granted,

  /// El usuario rechazó el diálogo del SO (esta vez; todavía puede volver a
  /// pedirse). El caller lo registra como «sin ubicación».
  denied,

  /// No hay nada que pedir: aviso de Ajustes mostrado u omitido, o servicios
  /// apagados. El caller no hace nada más.
  blocked;

  /// `true` si el caller debe seguir con la adquisición de la posición.
  bool get proceed => this == LocationFlowOutcome.granted;
}
