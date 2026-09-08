import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';

/// Wraps a Coach Hub section [child] in a [NoTransitionPage] so switching
/// between sidebar destinations swaps the content area INSTANTLY, with no
/// cross-fade.
///
/// Why this exists (bug W-COACH-NAV-01):
/// The section routes originally used `GoRoute.builder`, which makes go_router
/// synthesize a default platform [Page] with a fade transition. During that
/// fade the outgoing and incoming section widgets are BOTH mounted for a few
/// hundred ms, so their content visibly overlaps inside the shell's content
/// area (e.g. Biblioteca's exercise cards bleeding through the Pagos screen).
///
/// The shell wrapper itself already uses [NoTransitionPage]; the section pages
/// nested under it must do the same, otherwise the child transition still
/// runs. Using this helper in every section's `pageBuilder` keeps the swap
/// instant and the two screens from co-existing on screen.
///
/// Deliberately scoped to the Coach Hub (web) router — the mobile app relies
/// on its own `_noAnim` helper and platform transitions elsewhere, so we do
/// NOT touch the shared `AppTheme.pageTransitionsTheme`.
Page<void> coachHubPage(Widget child, {LocalKey? key}) {
  return NoTransitionPage<void>(key: key, child: child);
}

/// [coachHubPage] + entrada fade-slide, para las secciones que NO la
/// implementan por dentro.
///
/// **Por qué existen las dos variantes.** Como la página no transiciona (ver
/// arriba), la entrada de una sección es responsabilidad de la sección. Once
/// ya la tenían — Dashboard, Alumnos, Pagos, Planes, Perfil público y demás
/// envuelven sus bloques en [TreinoFadeSlideIn] con `AppMotion.stagger`, que
/// es más rico que un fundido único: los pedazos entran en cascada. Ocho no
/// tenían nada, así que aparecían de golpe. Ir de Dashboard a Pagos se sentía
/// terminado y de Dashboard a Agenda, roto — y la diferencia no estaba en
/// ninguna decisión, sólo en qué PR se acordó de la entrada.
///
/// Esta variante le da a esas ocho el fundido que les faltaba **sin** tocar a
/// las once que ya escalonan: envolverlas también multiplicaría las opacidades
/// y sumaría los desplazamientos (12 px de afuera + 12 px de adentro), que se
/// ve peor que no animar.
///
/// Entonces, para una sección nueva:
/// - ¿tiene bloques que ameriten cascada? → [coachHubPage] + [TreinoFadeSlideIn]
///   por bloque con `delay: AppMotion.stagger(i)`.
/// - ¿es una pantalla de una pieza? → [coachHubPageAnimated] y listo.
///
/// Lo que NO es válido es la tercera opción, que es la que teníamos: ninguna.
Page<void> coachHubPageAnimated(Widget child, {LocalKey? key}) {
  return coachHubPage(TreinoFadeSlideIn(child: child), key: key);
}
