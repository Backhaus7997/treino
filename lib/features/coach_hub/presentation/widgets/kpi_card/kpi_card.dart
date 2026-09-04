import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../../../../app/theme/app_motion.dart';
import '../../../../../app/theme/app_palette.dart';
import '../../../../../app/theme/tokens/components/treino_card_tokens.dart';
import '../../../../../app/theme/tokens/components/treino_kpi_card_tokens.dart';
import '../../../../../app/theme/tokens/primitives.dart';
import '../../../../../core/widgets/motion/treino_shimmer.dart';
import '../preview_wrapper.dart';
import '../treino_interactive_state.dart';

/// Previews del kit — Finding W3.
@Preview(name: 'KpiCard — normal', wrapper: coachHubPreviewWrapper)
Widget kpiCardPreview() => const KpiCard(
      value: '1.234',
      label: 'Alumnos activos',
      delta: '+12%',
      deltaPositive: true,
    );

@Preview(name: 'KpiCard — loading', wrapper: coachHubPreviewWrapper)
Widget kpiCardLoadingPreview() =>
    const KpiCard(value: '', label: '', loading: true);

@Preview(name: 'KpiCard — con sublabel', wrapper: coachHubPreviewWrapper)
Widget kpiCardSublabelPreview() => const KpiCard(
      value: r'$86.000',
      label: 'Por cobrar',
      sublabel: '3 vencidos',
    );

/// KPI Card del kit Coach Hub Web — Fase 1 (orden mockup alineado en Fase 2,
/// ADR-D2-04).
///
/// Muestra una métrica clave (label + value + delta/sublabel opcionales) con
/// soporte de:
/// - Estado loading: skeleton shimmer (TreinoShimmer).
/// - Hover/pressed/focus: vía TreinoInteractiveState (fuente única de verdad).
/// - Cambio de borde/fondo sin sombra (elevation-free, ADR-SH-006).
/// - onTap opcional: focusable, activable por teclado (Enter/Space) y expone
///   Semantics(button: true) — accesible sin mouse.
/// - Tokens: TreinoKpiCardTokens.of(context) — nunca hex inline.
/// - Ambos temas dark y light.
///
/// Orden visual (label -> value -> delta -> sublabel): `sublabel` es
/// data-honest (ADR-D2-04) — solo se pasa cuando hay una fuente real detrás,
/// nunca se inventa para calzar el mockup.
///
/// Uso:
/// ```dart
/// KpiCard(
///   value: '1.234',
///   label: 'Alumnos activos',
///   delta: '+12%',
///   deltaPositive: true,
///   onTap: () => nav.push('/alumnos'),
/// )
/// ```
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.value,
    required this.label,
    this.valueBuilder,
    this.delta,
    this.deltaPositive,
    this.sublabel,
    this.loading = false,
    this.onTap,
  });

  /// Valor principal de la métrica (ej: "1.234", "98%").
  ///
  /// Cuando se pasa [valueBuilder], este texto se sigue usando como fallback
  /// semántico pero no se pinta.
  final String value;

  /// Reemplaza el [Text] del valor por un widget propio, recibiendo el
  /// [TextStyle] exacto que usaría la card.
  ///
  /// Existe para que un consumidor pueda animar el número sin perder la
  /// tipografía del kit — el caso real es Pagos, donde `main` cuenta los
  /// montos con `TreinoCountUp` (ca5ba90c). Sin esto, migrar Pagos al kit
  /// obligaba a elegir entre el diseño y la animación.
  ///
  /// Opcional y aditivo: los consumidores existentes no cambian.
  final Widget Function(BuildContext context, TextStyle style)? valueBuilder;

  /// Etiqueta descriptiva de la métrica.
  final String label;

  /// Variación opcional (ej: "+12%", "-5%"). Null = sin delta.
  final String? delta;

  /// `true` = variación positiva (color accent), `false` = negativa (danger).
  final bool? deltaPositive;

  /// Texto secundario opcional debajo del value/delta (ej: "3 vencidos").
  ///
  /// Data-honest (ADR-D2-04, Fase 2): solo se pasa cuando hay una fuente de
  /// dato real detrás — nunca se inventa para calzar el mockup.
  final String? sublabel;

  /// `true` mientras se cargan los datos — muestra skeleton.
  final bool loading;

  /// Acción al tocar la card. Null = sin interactividad.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TreinoInteractiveState(
      onTap: onTap,
      builder: (ctx, states) {
        final tokens = TreinoKpiCardTokens.of(ctx);
        final p = AppPalette.of(ctx);

        Widget content;
        if (loading) {
          content = _SkeletonContent(tokens: tokens);
        } else {
          content = _CardContent(
            value: value,
            label: label,
            valueBuilder: valueBuilder,
            delta: delta,
            deltaPositive: deltaPositive,
            sublabel: sublabel,
            tokens: tokens,
            palette: p,
          );
        }

        final highlighted = states.hovered || states.pressed;

        return AnimatedContainer(
          key: const Key('kpi_card_root'),
          duration: AppMotion.resolve(ctx, AppMotion.fast),
          curve: AppMotion.standard,
          decoration: BoxDecoration(
            // El glow de la welcome card, al 6% en vez del 12%: son cuatro
            // en fila y a intensidad plena la tira compite con el hero en vez
            // de acompañarlo. El hover lo sube — es el mismo gesto de siempre
            // (la card se aclara), contado en el idioma de la pantalla.
            gradient: TreinoCardTokens.glow(
              ctx,
              alpha: highlighted ? 0.14 : 0.06,
            ),
            border: Border.all(
              color: highlighted ? p.borderHover : tokens.border,
            ),
            borderRadius:
                BorderRadius.circular(TreinoKpiCardTokens.borderRadius),
            // Sin boxShadow — elevation-free por spec ADR-SH-006.
          ),
          child: Padding(
            padding: const EdgeInsets.all(TreinoKpiCardTokens.padding),
            child: content,
          ),
        );
      },
    );
  }
}

/// Contenido del skeleton (loading).
class _SkeletonContent extends StatelessWidget {
  const _SkeletonContent({required this.tokens});

  final TreinoKpiCardTokens tokens;

  @override
  Widget build(BuildContext context) {
    return TreinoShimmer(
      child: Column(
        key: const Key('kpi_card_skeleton'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Skeleton del label (orden mockup: label arriba — ADR-D2-04)
          Container(
            width: 120,
            height: 14,
            decoration: BoxDecoration(
              color: tokens.border,
              borderRadius:
                  BorderRadius.circular(TreinoKpiCardTokens.borderRadius / 2),
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          // Skeleton del valor
          Container(
            width: 80,
            height: 28,
            decoration: BoxDecoration(
              color: tokens.border,
              borderRadius:
                  BorderRadius.circular(TreinoKpiCardTokens.borderRadius / 2),
            ),
          ),
        ],
      ),
    );
  }
}

/// Contenido con datos reales.
class _CardContent extends StatelessWidget {
  const _CardContent({
    required this.value,
    required this.label,
    required this.valueBuilder,
    required this.delta,
    required this.deltaPositive,
    required this.sublabel,
    required this.tokens,
    required this.palette,
  });

  final String value;
  final String label;
  final Widget Function(BuildContext, TextStyle)? valueBuilder;
  final String? delta;
  final bool? deltaPositive;
  final String? sublabel;
  final TreinoKpiCardTokens tokens;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Orden mockup Fase 2 (ADR-D2-04): label -> value -> delta -> sublabel.
        Text(
          label,
          style: TextStyle(
            fontFamily: AppFonts.barlow,
            fontWeight: FontWeight.w400,
            fontSize: 12,
            color: tokens.titleColor,
          ),
        ),
        const SizedBox(height: AppSpacing.hairline),
        Builder(
          builder: (ctx) {
            final valueStyle = TextStyle(
              fontFamily: AppFonts.barlowCondensed,
              fontWeight: FontWeight.w700,
              fontSize: 28,
              color: tokens.valueColor,
            );
            return valueBuilder?.call(ctx, valueStyle) ??
                Text(value, style: valueStyle);
          },
        ),
        if (delta != null) ...[
          const SizedBox(height: AppSpacing.s8),
          Text(
            delta!,
            style: TextStyle(
              fontFamily: AppFonts.barlow,
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: deltaPositive == true
                  ? tokens.variationPositiveColor
                  : tokens.variationNegativeColor,
            ),
          ),
        ],
        if (sublabel != null) ...[
          const SizedBox(height: AppSpacing.hairline),
          Text(
            sublabel!,
            style: TextStyle(
              fontFamily: AppFonts.barlow,
              fontWeight: FontWeight.w400,
              fontSize: 11,
              color: tokens.titleColor,
            ),
          ),
        ],
      ],
    );
  }
}
