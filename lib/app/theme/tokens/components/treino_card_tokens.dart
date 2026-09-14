import 'package:flutter/material.dart';

import '../primitives.dart';
import '../../app_palette.dart';

/// Capa 3 — Tokens de componente para cards TREINO.
///
/// Sigue el patrón `static T method(BuildContext)`: lee [AppPalette.of(ctx)]
/// para color y [AppRadius] para forma. NUNCA usa hex inline.
/// Las cards no tienen sombra: [boxShadow] == `[]`.
///
/// Uso:
/// ```dart
/// Container(
///   decoration: BoxDecoration(
///     color: TreinoCardTokens.background(context),
///     border: Border.all(color: TreinoCardTokens.border(context)),
///     borderRadius: BorderRadius.circular(TreinoCardTokens.borderRadius),
///     boxShadow: TreinoCardTokens.boxShadow,
///   ),
/// )
/// ```
abstract final class TreinoCardTokens {
  /// Color de fondo de la card — delega a `AppPalette.bgCard`.
  static Color background(BuildContext ctx) => AppPalette.of(ctx).bgCard;

  /// Color de borde de la card — delega a `AppPalette.border`.
  static Color border(BuildContext ctx) => AppPalette.of(ctx).border;

  /// Radio de borde de la card (referencias a [AppRadius]).
  static const double borderRadius = AppRadius.md;

  /// Las cards TREINO no tienen sombra — lista siempre vacía.
  /// Ver `docs/design-system.md` — sección Cards.
  static const List<BoxShadow> boxShadow = [];

  /// Glow mint en diagonal desde la esquina superior izquierda (#341).
  ///
  /// Nació inline en la welcome card del dashboard, y ahí se quedó: la
  /// welcome card lo tenía y los KPIs y los paneles de la misma pantalla
  /// quedaban planos, como si fueran dos diseños distintos conviviendo.
  ///
  /// `BoxDecoration` no admite `color` y `gradient` a la vez, así que el
  /// fondo de la card pasa a ser los dos últimos stops: fuera del glow se ve
  /// idéntico a [background].
  ///
  /// [alpha] gradúa la intensidad. La welcome card usa el default; las
  /// superficies chicas y repetidas (KPIs, paneles) van más abajo — cuatro
  /// cards al 12% en fila no leen como familia, leen como mancha verde, y le
  /// comen la jerarquía justamente a la card que tiene que dominar.
  ///
  /// **El mismo alpha NO pesa lo mismo en los dos temas.** Sobre el
  /// casi-negro de dark, un mint translúcido SUMA luminancia y se lee como un
  /// brillo en la esquina. Sobre el blanco de light, TIÑE: el mismo 12% pasa
  /// de "reflejo" a "mancha verde", y como la rampa llega hasta el 45% de la
  /// diagonal, cubre casi media card. Cuatro KPIs en fila en tema claro se
  /// veían como un error de render, no como una decisión.
  ///
  /// Por eso light recibe [_lightAlphaFactor] del alpha pedido y una rampa más
  /// corta ([_lightStop]): el glow se concentra en la esquina en vez de lavar
  /// la superficie. La bifurcación se resuelve ACÁ y no en el widget — mismo
  /// criterio que `AppPalette.accentText`, que existe justamente para que
  /// nadie ramifique por `Theme.of(context).brightness` en la capa de
  /// presentación.
  static LinearGradient glow(BuildContext ctx, {double alpha = 0.12}) {
    final bg = background(ctx);
    // La luminancia del PROPIO fondo, no `Theme.of(ctx).brightness`.
    //
    // El glow compone sobre `bgCard`, así que la superficie que lo recibe es
    // la que tiene que decidir. Y `brightness` es un campo aparte de
    // `ThemeData` que nada obliga a mantener en sync con la paleta: un tema
    // armado con la paleta oscura y el `brightness` por default (que es
    // `light`) tomaría la rama equivocada y nadie se enteraría.
    final isLight = bg.computeLuminance() > 0.5;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        AppPalette.of(ctx)
            .accent
            .withValues(alpha: isLight ? alpha * _lightAlphaFactor : alpha),
        bg,
        bg,
      ],
      stops: [0.0, isLight ? _lightStop : _darkStop, 1.0],
    );
  }

  /// Cuánto del alpha pedido sobrevive en tema claro. Ver [glow].
  static const double _lightAlphaFactor = 0.5;

  /// Dónde termina la rampa del glow. En light se corta antes para que el
  /// tinte quede en la esquina y no se derrame sobre el contenido.
  static const double _darkStop = 0.45;
  static const double _lightStop = 0.28;
}
