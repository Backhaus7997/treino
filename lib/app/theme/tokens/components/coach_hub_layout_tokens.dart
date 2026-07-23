/// Capa 3 — Tokens de layout del shell Coach Hub Web.
///
/// Define dimensiones fijas del shell: ancho de sidebar, altura de topbar,
/// anchos máximos de contenido, etc. No depende de [BuildContext] — todos
/// los valores son `static const double` (no varían por tema).
///
/// Uso:
/// ```dart
/// SizedBox(
///   width: CoachHubLayoutTokens.sidebarExpandedWidth,
///   child: CoachHubSidebar(),
/// )
/// ```
abstract final class CoachHubLayoutTokens {
  /// Ancho del sidebar expandido — `240.0 px` (spec REQ-SH-001).
  static const double sidebarExpandedWidth = 240.0;

  /// Ancho del sidebar colapsado — `72.0 px` (spec REQ-SH-001).
  static const double sidebarCollapsedWidth = 72.0;

  /// Altura del top bar — `64.0 px` (spec REQ-SH-020).
  static const double topBarHeight = 64.0;

  /// Ancho máximo del área de contenido principal — `1240.0 px`
  /// (spec REQ-SH-008, REQ-SH-020).
  static const double contentMaxWidth = 1240.0;

  /// Altura de cada ítem del sidebar — `48.0 px` (spec REQ-SH-003, REQ-SH-020).
  static const double sidebarItemHeight = 48.0;

  /// Diámetro del avatar circular en el footer del sidebar — `44.0 px`
  /// (spec REQ-SH-005, REQ-SH-020).
  static const double sidebarAvatarDiameter = 44.0;

  /// Tamaño del badge numérico en ítems del sidebar — `16.0 px`
  /// (spec REQ-SH-003, REQ-SH-020).
  static const double sidebarBadgeSize = 16.0;
}
