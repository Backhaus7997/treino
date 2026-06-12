/// Breakpoints responsivos del shell web del Coach Hub (ADR-CHW-004).
///
/// Función pura `viewportFor()` sin dependencia de Flutter — testeable sin
/// `pumpWidget`. El `CoachHubScaffold` la consume vía
/// `MediaQuery.sizeOf(context).width` (la rama responsiva se agrega en W1.3).
library;

/// >= 1280 px: desktop, el sidebar respeta `sidebarCollapsedProvider`.
const double kDesktopBreakpoint = 1280;

/// 1024–1279 px: compact, el sidebar queda forzado a colapsado (toggle off).
const double kCompactBreakpoint = 1024;

/// < 768 px: mobile, `MobileBanner` reemplaza el scaffold (W1.3).
const double kMobileBreakpoint = 768;

/// Clasificación de viewport derivada del ancho disponible.
enum Viewport { mobile, compact, desktop }

/// Mapea un ancho (en px lógicos) a su [Viewport].
///
/// - `< 768` → [Viewport.mobile]
/// - `768 … 1279` → [Viewport.compact]
/// - `>= 1280` → [Viewport.desktop]
Viewport viewportFor(double width) {
  if (width < kMobileBreakpoint) return Viewport.mobile;
  if (width < kDesktopBreakpoint) return Viewport.compact;
  return Viewport.desktop;
}
