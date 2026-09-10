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
      // Secundaria DESTACADA: misma caja que la secundaria, texto en acento.
      //
      // Va `accentText` y NO `accent`, y el motivo está medido: el acento
      // (mint500) sobre una card blanca da 1,64:1 contra los 4,5 que pide WCAG
      // AA. El botón «Pago» del detalle se leía lavado y el PF lo reportó
      // así. En oscuro los dos tokens son el MISMO color, y por eso la suite
      // —que corre en oscuro— nunca lo vio. Que la decisión viva acá y no en
      // cada llamador es lo que impide que vuelva a pasar.
      TreinoButtonVariant.secondaryAccent => TreinoButtonVisual._(
          background: AppColorPrimitives.transparent,
          hoverBackground: p.surfaceSubtle,
          foreground: p.accentText,
          borderColor: p.border,
          hoverBorderColor: p.borderHover,
        ),
      // DESTRUCTIVA. Borde y texto en `danger`, sin relleno: la acción que
      // borra no se ofrece como un CTA lleno, pero tampoco se disimula.
      TreinoButtonVariant.danger => TreinoButtonVisual._(
          background: AppColorPrimitives.transparent,
          hoverBackground: p.danger.withValues(alpha: 0.08),
          foreground: p.danger,
          borderColor: p.danger,
          hoverBorderColor: p.danger,
        ),
      // La terciaria en acento: sin caja, texto que invita. Es el «+ Asignar
      // rutina» / «+ Registrar pago» que estaba escrito como `TextButton` con
      // el color a mano en cada callsite.
      TreinoButtonVariant.ghostAccent => TreinoButtonVisual._(
          background: AppColorPrimitives.transparent,
          hoverBackground: p.surfaceSubtle,
          foreground: p.accentText,
          borderColor: AppColorPrimitives.transparent,
          hoverBorderColor: AppColorPrimitives.transparent,
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

/// Las jerarquías de acción del producto. No es una lista suelta: es una
/// grilla de dos ejes más el CTA.
///
/// |            | neutro           | acento                 |
/// |------------|------------------|------------------------|
/// | con borde  | [secondary]      | [secondaryAccent]      |
/// | sin borde  | [ghost]          | [ghostAccent]          |
///
/// Y arriba de todo [primary], el CTA relleno — uno por pantalla.
///
/// Las cinco ya existían en el producto; lo que no existía era el nombre, así
/// que cada pantalla las volvía a inventar con colores y paddings propios. Una
/// variante NUEVA, en cambio, es vocabulario que el usuario tiene que
/// aprender: antes de agregar la sexta, mirar si alguna de estas cinco dice lo
/// mismo.
///
/// Las dos de acento llevan `accentText` y no `accent`, y eso NO es un detalle
/// de implementación: es el arreglo de contraste de #1056, blindado adentro
/// del token para que ningún callsite lo vuelva a resolver mal.
enum TreinoButtonVariant {
  primary,
  secondary,
  secondaryAccent,
  ghost,
  ghostAccent,

  /// Fuera de la grilla a propósito: [danger] no es un nivel de énfasis, es
  /// una advertencia. Va sólo donde la acción destruye algo.
  danger,
}

/// Dos tamaños. `sm` para densidad de tabla y de fila; `md` para diálogos y
/// para el CTA de una sección.
///
/// UN padding por tamaño y UN tap target por tamaño, que es exactamente lo que
/// no había: `alumno_detail_screen.dart` tenía siete paddings distintos y seis
/// tamaños de ícono en un solo archivo, y de 59 botones sólo 6 acotaban su tap
/// target.
enum TreinoButtonSize {
  /// Densidad de TABLA. No es «sm más chico»: es el tamaño que impone la fila.
  ///
  /// `TreinoTableTokens.rowHeight` son 48 px y `cellPaddingV` 12 arriba y 12
  /// abajo, así que el alto útil de una celda son 24 y no hay negociación. Un
  /// botón de 32 ahí adentro desborda. Los cuatro íconos de acción del roster
  /// medían exactamente esto —24x24— por accidente, vía `visualDensity`; acá
  /// lo miden a propósito, y con 4 px de aire alrededor del ícono en vez de 3.
  ///
  /// 24x24 es el piso de WCAG 2.2 (2.5.8) y sólo alcanza CON separación entre
  /// botones. Quien los agrupe tiene que ponerla.
  xs(
      height: 24,
      paddingH: AppSpacing.hairline,
      fontSize: AppTextSize.caption,
      iconSize: 16),
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
