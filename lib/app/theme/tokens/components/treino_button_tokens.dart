import 'package:flutter/material.dart';

import '../primitives.dart';
import '../../app_palette.dart';

/// Capa 3 — Tokens de componente para botones primarios TREINO.
///
/// Sigue el patrón `static T method(BuildContext)`: lee [AppPalette.of(ctx)]
/// para color y [AppRadius] para forma. NUNCA usa hex inline.
///
/// Uso:
/// ```dart
/// Container(
///   color: TreinoButtonTokens.background(context),
///   child: Text('Guardar', style: TextStyle(color: TreinoButtonTokens.foreground(context))),
/// )
/// ```
abstract final class TreinoButtonTokens {
  /// Color de fondo del botón primario — delega a `AppPalette.accent`.
  static Color background(BuildContext ctx) => AppPalette.of(ctx).accent;

  /// Color de texto/icono sobre el botón primario.
  ///
  /// El acento mint es claro, entonces usamos el ink más profundo para
  /// garantizar contraste WCAG AA sobre el fondo mint.
  // ignore: avoid_unused_parameters
  static Color foreground(BuildContext ctx) {
    // El acento (mint) es el mismo en dark y light, pero el ink de fondo
    // varía — usamos ink950 como foreground absoluto para CTA.
    return AppColorPrimitives.ink950;
  }

  /// Radio de borde del botón primario (referencias a [AppRadius]).
  static const double borderRadius = AppRadius.sm;

  /// Resuelve los colores de una [TreinoButtonVariant] según el tema activo.
  static TreinoButtonVisual of(BuildContext ctx, TreinoButtonVariant variant) {
    final p = AppPalette.of(ctx);
    return switch (variant) {
      // El CTA. El hover baja la opacidad del acento en vez de mezclar otro
      // color: es el patrón que ya usaba el «Registrar pago» de Pagos, y
      // mantiene el contraste del foreground intacto.
      TreinoButtonVariant.primary => TreinoButtonVisual._(
          background: p.accent,
          hoverBackground: p.accent.withValues(alpha: 0.88),
          foreground: foreground(ctx),
          borderColor: AppColorPrimitives.transparent,
          hoverBorderColor: AppColorPrimitives.transparent,
        ),
      // La acción secundaria: se lee, no grita. Borde en reposo y relleno
      // neutro al hover.
      TreinoButtonVariant.secondary => TreinoButtonVisual._(
          background: AppColorPrimitives.transparent,
          hoverBackground: p.surfaceSubtle,
          foreground: p.textPrimary,
          borderColor: p.border,
          hoverBorderColor: p.borderHover,
        ),
      // La terciaria: sin caja hasta que la tocás. Para acciones que no
      // compiten (cancelar, «ver más»).
      TreinoButtonVariant.ghost => TreinoButtonVisual._(
          background: AppColorPrimitives.transparent,
          hoverBackground: p.surfaceSubtle,
          foreground: p.textMuted,
          borderColor: AppColorPrimitives.transparent,
          hoverBorderColor: AppColorPrimitives.transparent,
        ),
    };
  }
}

/// Las tres jerarquías de acción. Más variantes que estas tres es pedirle al
/// usuario que aprenda un vocabulario que no le sirve.
enum TreinoButtonVariant { primary, secondary, ghost }

/// Dos tamaños. `sm` para densidad de tabla y de fila; `md` para diálogos y
/// para el CTA de una sección.
///
/// UN padding por tamaño y UN tap target por tamaño, que es exactamente lo que
/// no había: `alumno_detail_screen.dart` tenía siete paddings distintos y seis
/// tamaños de ícono en un solo archivo, y de 59 botones sólo 6 acotaban su tap
/// target.
enum TreinoButtonSize {
  sm(
      height: 32,
      paddingH: AppSpacing.s12,
      fontSize: AppTextSize.bodyDense,
      iconSize: 16),
  md(
      height: 40,
      paddingH: AppSpacing.s18,
      fontSize: AppTextSize.body,
      iconSize: 18);

  const TreinoButtonSize({
    required this.height,
    required this.paddingH,
    required this.fontSize,
    required this.iconSize,
  });

  final double height;
  final double paddingH;
  final double fontSize;
  final double iconSize;

  /// Separación entre el ícono y el label. Una sola, para los dos tamaños.
  static const double gap = AppSpacing.s8;
}

/// Colores ya resueltos de una variante. Inmutable y sin `BuildContext`
/// adentro: se pide una vez por build y se consulta.
@immutable
class TreinoButtonVisual {
  const TreinoButtonVisual._({
    required this.background,
    required this.hoverBackground,
    required this.foreground,
    required this.borderColor,
    required this.hoverBorderColor,
  });

  final Color background;
  final Color hoverBackground;
  final Color foreground;
  final Color borderColor;
  final Color hoverBorderColor;
}
