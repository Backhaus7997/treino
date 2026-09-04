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
  static LinearGradient glow(BuildContext ctx, {double alpha = 0.12}) {
    final bg = background(ctx);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        AppPalette.of(ctx).accent.withValues(alpha: alpha),
        bg,
        bg,
      ],
      stops: const [0.0, 0.45, 1.0],
    );
  }
}
