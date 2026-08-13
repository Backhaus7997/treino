import 'package:flutter/material.dart';

import '../../../../../app/theme/app_motion.dart';
import '../../../../../app/theme/app_palette.dart';
import '../../../../../app/theme/tokens/components/treino_kpi_card_tokens.dart';
import '../../../../../core/widgets/motion/treino_shimmer.dart';
import '../../../../../core/widgets/motion/treino_tappable.dart';

/// KPI Card del kit Coach Hub Web — Fase 1.
///
/// Muestra una métrica clave (value + label + delta opcional) con soporte de:
/// - Estado loading: skeleton shimmer (TreinoShimmer).
/// - Hover: cambio de borde/fondo sin sombra (elevation-free, ADR-SH-006).
/// - onTap opcional: envuelto en TreinoTappable.
/// - Tokens: TreinoKpiCardTokens.of(context) — nunca hex inline.
/// - Ambos temas dark y light.
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
class KpiCard extends StatefulWidget {
  const KpiCard({
    super.key,
    required this.value,
    required this.label,
    this.delta,
    this.deltaPositive,
    this.loading = false,
    this.onTap,
  });

  /// Valor principal de la métrica (ej: "1.234", "98%").
  final String value;

  /// Etiqueta descriptiva de la métrica.
  final String label;

  /// Variación opcional (ej: "+12%", "-5%"). Null = sin delta.
  final String? delta;

  /// `true` = variación positiva (color accent), `false` = negativa (danger).
  final bool? deltaPositive;

  /// `true` mientras se cargan los datos — muestra skeleton.
  final bool loading;

  /// Acción al tocar la card. Null = sin interactividad.
  final VoidCallback? onTap;

  @override
  State<KpiCard> createState() => _KpiCardState();
}

class _KpiCardState extends State<KpiCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = TreinoKpiCardTokens.of(context);
    final p = AppPalette.of(context);

    Widget content;
    if (widget.loading) {
      content = _SkeletonContent(tokens: tokens);
    } else {
      content = _CardContent(
        value: widget.value,
        label: widget.label,
        delta: widget.delta,
        deltaPositive: widget.deltaPositive,
        tokens: tokens,
        palette: p,
      );
    }

    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: _hovered
            ? tokens.border.withValues(alpha: 0.08)
            : tokens.background,
        border: Border.all(
          color: _hovered ? p.borderHover : tokens.border,
        ),
        borderRadius: BorderRadius.circular(TreinoKpiCardTokens.borderRadius),
        // Sin boxShadow — elevation-free por spec ADR-SH-006.
      ),
      child: Padding(
        padding: const EdgeInsets.all(TreinoKpiCardTokens.padding),
        child: content,
      ),
    );

    final interactive = widget.onTap != null
        ? TreinoTappable(onTap: widget.onTap, child: card)
        : card;

    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppMotion.resolve(context, AppMotion.fast),
        curve: AppMotion.standard,
        child: KeyedSubtree(
          key: const Key('kpi_card_root'),
          child: interactive,
        ),
      ),
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
          const SizedBox(height: 8),
          // Skeleton del label
          Container(
            width: 120,
            height: 14,
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
    required this.delta,
    required this.deltaPositive,
    required this.tokens,
    required this.palette,
  });

  final String value;
  final String label;
  final String? delta;
  final bool? deltaPositive;
  final TreinoKpiCardTokens tokens;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontFamily: 'BarlowCondensed',
            fontWeight: FontWeight.w700,
            fontSize: 28,
            color: tokens.valueColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Barlow',
            fontWeight: FontWeight.w400,
            fontSize: 12,
            color: tokens.titleColor,
          ),
        ),
        if (delta != null) ...[
          const SizedBox(height: 8),
          Text(
            delta!,
            style: TextStyle(
              fontFamily: 'Barlow',
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: deltaPositive == true
                  ? tokens.variationPositiveColor
                  : tokens.variationNegativeColor,
            ),
          ),
        ],
      ],
    );
  }
}
