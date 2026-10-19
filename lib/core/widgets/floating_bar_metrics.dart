/// Medidas de los botones circulares que flotan sobre el contenido
/// (atrás / editar / seguir) en pantallas con `Stack` + `Positioned(top: 0)`.
///
/// Fuente única (#1559): el botón y el espacio que el contenido reserva debajo
/// salen de las MISMAS constantes, así que no pueden desincronizarse (antes el
/// botón medía 56 y el encabezado reservaba 64 / 80 "a ojo" en cada pantalla).
abstract final class FloatingBarMetrics {
  /// Separación entre el borde superior del área segura y el botón.
  static const double topInset = 8;

  /// Separación horizontal contra el borde de la pantalla.
  static const double sideInset = 12;

  /// Alto del botón (`IconButton` con tap target de 48).
  static const double buttonSize = 48;

  /// Aire entre el botón y el contenido que arranca debajo.
  static const double clearance = 8;

  /// Alto que el contenido debe reservar arriba para no quedar bajo el botón.
  /// El área segura superior ya la consume el contenedor de la ruta.
  static const double reservedHeight = topInset + buttonSize + clearance;
}
