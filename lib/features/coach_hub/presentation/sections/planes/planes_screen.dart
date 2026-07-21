// NOTE: el Scaffold y el SafeArea los provee CoachHubScaffold (el shell).
// NO los agregues acá (ADR-CHW-005).
//
// PlanesScreen shell (WU-03, Fase 10): header + subtítulo + banner honesto de
// descope + KPI strip, cableados a `tarifasResumenProvider`
// (`tarifas_provider.dart`).
//
// ADR-F10-01 (descope, WU-01): sin catálogo de "planes comerciales"
// vendibles — solo la tarifa real por alumno (`AthleteBilling`), agrupada.
// El banner de descope materializa esa decisión para el trainer: la sección
// es de solo lectura hoy. La grilla de tarifas (WU-04) reemplaza el
// placeholder al final de este archivo.
//
// Todas las strings están en español hardcodeado + comentario // i18n.
// NO se usa AppL10n en este archivo (constraint C-6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/payment_format.dart'
    show fmtArs;

import '../../widgets/coach_hub_widgets.dart' show KpiCard, TreinoSectionHeader;
import 'tarifas_model.dart';
import 'tarifas_provider.dart';

// ── PlanesScreen ─────────────────────────────────────────────────────────────

/// Sección Planes comerciales del Coach Hub web.
///
/// Sigue el contrato de sección (ADR-CHW-005): sin Scaffold propio, sin
/// SafeArea. El shell [CoachHubScaffold] provee el chrome.
class PlanesScreen extends ConsumerWidget {
  const PlanesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final resumenAsync = ref.watch(tarifasResumenProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header + subtítulo (staggered) ───────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: TreinoFadeSlideIn(
            delay: AppMotion.stagger(0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TreinoSectionHeader(
                  title: 'Planes comerciales', // i18n
                ),
                const SizedBox(height: AppSpacing.hairline),
                Text(
                  'Precios que cobrás actualmente, agrupados por '
                  'tarifa', // i18n
                  style: TextStyle(color: palette.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
        ),

        // ── Banner de descope (read-only, ADR-F10-01) ─────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: TreinoFadeSlideIn(
            delay: AppMotion.stagger(1),
            child: const _DescopeBanner(),
          ),
        ),

        // ── KPI strip ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: TreinoFadeSlideIn(
            delay: AppMotion.stagger(2),
            child: _TarifasKpiRow(resumenAsync: resumenAsync),
          ),
        ),

        // WU-04: grid de tarifas (CoachHubDataTable/cards) debajo del strip.
      ],
    );
  }
}

// ── _DescopeBanner ───────────────────────────────────────────────────────────

/// Banner honesto que materializa el descope de ADR-F10-01: esta sección
/// muestra tarifas reales por alumno, no un catálogo de planes vendibles.
class _DescopeBanner extends StatelessWidget {
  const _DescopeBanner();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      key: const Key('planes_descope_banner'),
      padding: const EdgeInsets.all(AppSpacing.s14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(TreinoIcon.infoCircle, size: 18, color: palette.textMuted),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Text(
              'Estos son tus precios reales por alumno. La creación de '
              'planes comerciales vendibles llega más adelante.', // i18n
              style: TextStyle(color: palette.textMuted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ── _TarifasKpiRow ───────────────────────────────────────────────────────────

/// Fila de 3 KpiCard: Precio promedio / Alumnos con tarifa / Tarifas
/// distintas — derivadas de [TarifasResumen] (`tarifasResumenProvider`).
///
/// ADR-F10-02 (honestidad de datos, heredado de Pagos ADR-F9-01): sin deltas
/// de conversión/crecimiento inventados — no hay fuente mes-contra-mes real
/// para planes comerciales.
///
/// Layout responsive: mismo patrón que `PagosKpiRow` — 3 columnas iguales
/// desde ~900px de ancho, Wrap de 2 columnas debajo.
class _TarifasKpiRow extends StatelessWidget {
  const _TarifasKpiRow({required this.resumenAsync});

  final AsyncValue<TarifasResumen> resumenAsync;

  static const double _rowBreakpoint = 900;
  static const double _spacing = 12;

  @override
  Widget build(BuildContext context) {
    final loading = resumenAsync.isLoading;
    final resumen = resumenAsync.valueOrNull;

    final cards = <KpiCard>[
      KpiCard(
        label: 'Precio promedio', // i18n
        value: fmtArs(resumen?.precioPromedio ?? 0),
        sublabel:
            '${resumen?.alumnosConTarifa ?? 0} alumnos con tarifa', // i18n
        loading: loading,
      ),
      KpiCard(
        label: 'Alumnos con tarifa', // i18n
        value: '${resumen?.alumnosConTarifa ?? 0}',
        sublabel: '${resumen?.tarifasDistintas ?? 0} tarifas', // i18n
        loading: loading,
      ),
      KpiCard(
        label: 'Tarifas distintas', // i18n
        value: '${resumen?.tarifasDistintas ?? 0}',
        loading: loading,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _rowBreakpoint) {
          return Row(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: _spacing),
                Expanded(child: cards[i]),
              ],
            ],
          );
        }

        final itemWidth = (constraints.maxWidth - _spacing) / 2;
        return Wrap(
          spacing: _spacing,
          runSpacing: _spacing,
          children: [
            for (final card in cards) SizedBox(width: itemWidth, child: card),
          ],
        );
      },
    );
  }
}
