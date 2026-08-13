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
}
