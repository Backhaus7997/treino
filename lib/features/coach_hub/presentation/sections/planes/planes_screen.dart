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
// es de solo lectura hoy.
//
// Grid de tarifas + filtro por cadencia (WU-04, Fase 10): reemplaza el
// placeholder de WU-03. Filtro vía `TreinoFilterChips` (mismo patrón
// single-select que Pagos, `pagos_web_screen.dart`) sobre
// `planesFiltroProvider` (`planes_filtro_provider.dart`). El grid es
// read-only — sin CTA de edición (no hay mutación de tarifas cableada en
// esta fase).
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
import 'package:treino/core/widgets/motion/treino_shimmer.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/payment_format.dart'
    show fmtArs;

import '../../widgets/coach_hub_widgets.dart'
    show KpiCard, TreinoEmptyState, TreinoFilterChips, TreinoSectionHeader;
import 'planes_filtro_provider.dart';
import 'tarifas_model.dart';
import 'tarifas_provider.dart';
import 'widgets/tarifa_card.dart';

/// Etiquetas (es-AR) de cada [PlanesFiltroCadencia], en el orden en que se
/// muestran los chips.
const _kFiltroLabels = {
  PlanesFiltroCadencia.todas: 'Todas', // i18n
  PlanesFiltroCadencia.mensual: 'Mensual', // i18n
  PlanesFiltroCadencia.semanal: 'Semanal', // i18n
  PlanesFiltroCadencia.porSesion: 'Por sesión', // i18n
  PlanesFiltroCadencia.suelto: 'Suelto', // i18n
};

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
    final filtro = ref.watch(planesFiltroProvider);

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

        // ── Filtro por cadencia (chips) ────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: TreinoFadeSlideIn(
            delay: AppMotion.stagger(3),
            child: _TarifasFiltroChips(
              grupos: resumenAsync.valueOrNull?.grupos ?? const [],
              filtro: filtro,
            ),
          ),
        ),

        // ── Grid de tarifas (según filtro activo) ──────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: TreinoStateSwitcher(
              childKey: ValueKey('planes_filtro_${filtro.name}'),
              child: _TarifasGridBody(
                resumenAsync: resumenAsync,
                filtro: filtro,
              ),
            ),
          ),
        ),
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
        // ADR-F10-02 (tarifas_model.dart): mezcla mensual/semanal/porSesion/
        // suelto en un único promedio, no comparable entre cadencias — el
        // sublabel debe aclarar el caveat, no duplicar un conteo.
        sublabel: 'Mezcla cadencias, no comparable', // i18n
        loading: loading,
      ),
      KpiCard(
        label: 'Alumnos con tarifa', // i18n
        value: '${resumen?.alumnosConTarifa ?? 0}',
        sublabel: '${resumen?.tarifasDistintas ?? 0} '
            '${pluralizarEs(resumen?.tarifasDistintas ?? 0, 'tarifa', 'tarifas')}', // i18n
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

// ── _TarifasFiltroChips ─────────────────────────────────────────────────────

/// Filtro de cadencia de la grilla — mismo patrón single-select que
/// `PagosScreen` (`pagos_web_screen.dart`): un tap que vacía la selección es
/// un no-op, siempre hay un filtro activo.
///
/// [badgeCounts] cuenta GRUPOS por cadencia (no alumnos) — coherente con lo
/// que el chip filtra (grupos de tarifa, no billings individuales).
class _TarifasFiltroChips extends ConsumerWidget {
  const _TarifasFiltroChips({required this.grupos, required this.filtro});

  final List<TarifaGroup> grupos;
  final PlanesFiltroCadencia filtro;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badgeCounts = <String, int>{};
    for (final entry in _kFiltroLabels.entries) {
      if (entry.key == PlanesFiltroCadencia.todas) continue;
      final cadence = cadenceOfFiltro(entry.key);
      badgeCounts[entry.value] =
          grupos.where((g) => g.cadence == cadence).length;
    }

    return TreinoFilterChips(
      options: _kFiltroLabels.values.toList(),
      selected: {_kFiltroLabels[filtro]!},
      badgeCounts: badgeCounts,
      onChanged: (newSelected) {
        if (newSelected.isEmpty) return;
        final label = newSelected.first;
        for (final entry in _kFiltroLabels.entries) {
          if (entry.value == label) {
            ref.read(planesFiltroProvider.notifier).state = entry.key;
            break;
          }
        }
      },
    );
  }
}

// ── _TarifasGridBody ─────────────────────────────────────────────────────────

/// Resuelve los 4 estados del grid (loading/error/vacío/data) para el
/// [filtro] activo.
class _TarifasGridBody extends StatelessWidget {
  const _TarifasGridBody({required this.resumenAsync, required this.filtro});

  final AsyncValue<TarifasResumen> resumenAsync;
  final PlanesFiltroCadencia filtro;

  @override
  Widget build(BuildContext context) {
    if (resumenAsync.isLoading) return const _TarifasGridSkeleton();

    if (resumenAsync.hasError) {
      return _TarifasGridError(
        onRetry: () {
          final container = ProviderScope.containerOf(context);
          container.invalidate(trainerBillingsProvider);
        },
      );
    }

    final resumen = resumenAsync.valueOrNull;
    final grupos = resumen?.grupos ?? const <TarifaGroup>[];

    if (grupos.isEmpty) {
      return const TreinoEmptyState(
        key: Key('planes_tarifas_empty'),
        icon: TreinoIcon.emptyState,
        title: 'Todavía no configuraste tarifas', // i18n
        description: 'Definí el precio de cada alumno desde Alumnos o '
            'Pagos.', // i18n
      );
    }

    final cadence = cadenceOfFiltro(filtro);
    final filtrados =
        cadence == null ? grupos : grupos.where((g) => g.cadence == cadence);
    final visibles = filtrados.toList();

    if (visibles.isEmpty) {
      return TreinoEmptyState(
        key: const Key('planes_tarifas_empty_filtro'),
        icon: TreinoIcon.emptyState,
        title:
            'No hay tarifas ${_kFiltroLabels[filtro]!.toLowerCase()}', // i18n
      );
    }

    final masUsada = resumen?.masUsada;

    return _TarifasGrid(
      grupos: visibles,
      isMasUsada: (g) => masUsada != null && g == masUsada,
    );
  }
}

/// Grid responsive de [TarifaCard]: ~3 columnas desde 1200px, 2 columnas
/// entre 768-1200px (Coach Hub es desktop-only, `PagosKpiRow` doc).
class _TarifasGrid extends StatelessWidget {
  const _TarifasGrid({required this.grupos, required this.isMasUsada});

  final List<TarifaGroup> grupos;
  final bool Function(TarifaGroup) isMasUsada;

  static const double _wideBreakpoint = 1200;
  static const double _spacing = 12;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= _wideBreakpoint ? 3 : 2;
        final cardWidth =
            (constraints.maxWidth - _spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: _spacing,
          runSpacing: _spacing,
          children: [
            for (final grupo in grupos)
              SizedBox(
                width: cardWidth,
                child: TarifaCard(
                  key: Key(
                    'tarifa_card_${grupo.cadence.name}_${grupo.amountArs}',
                  ),
                  group: grupo,
                  masUsada: isMasUsada(grupo),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Skeleton shimmer del grid — 4 cards fantasma mientras
/// `trainerBillingsProvider` no resolvió.
class _TarifasGridSkeleton extends StatelessWidget {
  const _TarifasGridSkeleton();

  static const _skeletonCount = 4;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return TreinoShimmer(
      child: Wrap(
        key: const Key('planes_tarifas_skeleton'),
        spacing: 12,
        runSpacing: 12,
        children: [
          for (var i = 0; i < _skeletonCount; i++)
            Container(
              width: 280,
              height: 150,
              decoration: BoxDecoration(
                color: palette.bgCard,
                border: Border.all(color: palette.border),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
        ],
      ),
    );
  }
}

/// Estado de error del grid — mensaje honesto + "Reintentar" (invalida
/// `trainerBillingsProvider`, mismo patrón que `PagosWebTable`/
/// `CoachHubDataTable._ErrorState`).
class _TarifasGridError extends StatelessWidget {
  const _TarifasGridError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Error al cargar tarifas.', // i18n
              style: TextStyle(color: palette.textMuted, fontSize: 14),
            ),
            const SizedBox(height: AppSpacing.s12),
            TextButton(
              onPressed: onRetry,
              child: Text(
                'Reintentar', // i18n
                style: TextStyle(color: palette.accent, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
