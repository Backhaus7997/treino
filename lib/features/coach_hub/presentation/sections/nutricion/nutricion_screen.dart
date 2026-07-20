// NutricionScreen — overview cross-alumno de Nutrición del Coach Hub web
// (WU-04, Fase 6). Reemplaza `ProximamenteScreen` en `/nutricion`.
//
// Sigue el patrón de screens de sección (alumnos_screen.dart,
// invitaciones_screen.dart): `ConsumerWidget` sin `Scaffold`
// (ADR-CHW-005). Header (título + subtítulo) y `TreinoFilterChips` entran
// con `TreinoFadeSlideIn` staggered; la lista de [NutricionPlanRow] queda
// fuera del stagger — su cross-fade lo resuelve `TreinoStateSwitcher` sobre
// `nutricionEntriesProvider`.
//
// El tap en una fila navega al detalle del alumno (ADR-F6-03): esta screen
// es un overview cross-alumno, no instancia `PlanNutricionCard` (eso vive
// en el tab Nutrición de `alumno_detail_screen.dart`, Fase 3).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/theme/app_motion.dart';
import '../../../../../app/theme/app_palette.dart';
import '../../../../../app/theme/tokens/primitives.dart';
import '../../../../../core/widgets/motion/treino_fade_slide_in.dart';
import '../../../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../../../core/widgets/treino_icon.dart';
import '../../../../coach/application/trainer_link_providers.dart';
import '../../widgets/coach_hub_widgets.dart';
import 'nutricion_providers.dart';
import 'widgets/nutricion_plan_row.dart';

/// Overview cross-alumno de Nutrición (`/nutricion`) — WU-04.
class NutricionScreen extends ConsumerWidget {
  const NutricionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final entriesAsync = ref.watch(nutricionEntriesProvider);
    final filtro = ref.watch(nutricionFiltroProvider);
    final counts = nutricionFiltroCounts(entriesAsync.valueOrNull ?? const []);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s20,
        vertical: AppSpacing.s20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TreinoSectionHeader(
                  title: 'Nutrición', // i18n: Fase W6
                  count: counts[NutricionFiltro.todos],
                ),
                const SizedBox(height: AppSpacing.hairline),
                Text(
                  'Planes de alimentación de tus alumnos activos.', // i18n: Fase W6
                  style: TextStyle(color: palette.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s18),
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(1),
            child: _FiltroChips(filtro: filtro, counts: counts),
          ),
          const SizedBox(height: AppSpacing.s14),
          TreinoStateSwitcher(
            childKey: ValueKey(
              'nutricion_${_stateKeyOf(entriesAsync)}_${filtro.name}',
            ),
            child: entriesAsync.when(
              loading: () => const _LoadingList(),
              error: (e, _) => TreinoEmptyState(
                key: const Key('nutricion_error'),
                icon: TreinoIcon.errorState,
                title: 'No pudimos cargar tus alumnos.', // i18n: Fase W6
                ctaLabel: 'Reintentar', // i18n: Fase W6
                onCtaTap: () => ref.invalidate(trainerLinksStreamProvider),
              ),
              data: (entries) {
                final filtered = [
                  for (final entry in entries)
                    if (matchesNutricionFiltro(entry, filtro)) entry,
                ];
                if (filtered.isEmpty) {
                  return _EmptyNutricion(
                    filtro: filtro,
                    hasAnyAlumno: entries.isNotEmpty,
                    onIrAAlumnos: () => context.go('/alumnos'),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final entry in filtered) ...[
                      NutricionPlanRow(
                        key: ValueKey(
                          'nutricion_row_${entry.link.athleteId}',
                        ),
                        entry: entry,
                        onTap: () =>
                            context.go('/alumnos/${entry.link.athleteId}'),
                      ),
                      if (entry != filtered.last)
                        const SizedBox(height: AppSpacing.s8),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _stateKeyOf(AsyncValue<Object?> value) {
  if (value.hasError) return 'error';
  if (value.isLoading && !value.hasValue) return 'loading';
  return 'data';
}

/// Chips Todos/Con plan/Sin plan con badges de conteo real — single-select,
/// default Todos. Mismo patrón que `_FiltroChips` de `alumnos_screen.dart`.
class _FiltroChips extends ConsumerWidget {
  const _FiltroChips({required this.filtro, required this.counts});

  final NutricionFiltro filtro;
  final Map<NutricionFiltro, int> counts;

  static const _labels = {
    NutricionFiltro.todos: 'Todos', // i18n: Fase W6
    NutricionFiltro.conPlan: 'Con plan', // i18n: Fase W6
    NutricionFiltro.sinPlan: 'Sin plan', // i18n: Fase W6
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtroByLabel = {for (final e in _labels.entries) e.value: e.key};

    return TreinoFilterChips(
      options: _labels.values.toList(),
      selected: {_labels[filtro]!},
      badgeCounts: {
        for (final e in _labels.entries) e.value: counts[e.key] ?? 0,
      },
      onChanged: (newSelected) {
        // Single-select: un tap que vacía la selección (chip activo
        // desmarcado) es un no-op — siempre necesitamos un filtro activo.
        if (newSelected.isEmpty) return;
        final f = filtroByLabel[newSelected.first];
        if (f != null) ref.read(nutricionFiltroProvider.notifier).state = f;
      },
    );
  }
}

/// Skeleton de carga — columna de `NutricionPlanRow.loading` (shimmer del
/// kit vía `TreinoListRow`, nunca un `CircularProgressIndicator` seco).
class _LoadingList extends StatelessWidget {
  const _LoadingList();

  static const _rowCount = 5;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < _rowCount; i++) ...[
          if (i != 0) const SizedBox(height: AppSpacing.s8),
          NutricionPlanRow.loading(key: ValueKey('nutricion_loading_$i')),
        ],
      ],
    );
  }
}

/// Estado vacío honesto por caso (ADR-F6-06):
/// - sin alumnos activos vinculados → CTA a Alumnos.
/// - filtro "Con plan"/"Sin plan" sin resultados → mensaje específico, sin
///   CTA (el roster existe, solo no hay match para ese filtro).
class _EmptyNutricion extends StatelessWidget {
  const _EmptyNutricion({
    required this.filtro,
    required this.hasAnyAlumno,
    required this.onIrAAlumnos,
  });

  final NutricionFiltro filtro;
  final bool hasAnyAlumno;
  final VoidCallback onIrAAlumnos;

  @override
  Widget build(BuildContext context) {
    if (!hasAnyAlumno) {
      return TreinoEmptyState(
        key: const Key('nutricion_empty_sin_alumnos'),
        icon: TreinoIcon.emptyState,
        title: 'Todavía no tenés alumnos.', // i18n: Fase W6
        ctaLabel: 'Ir a Alumnos', // i18n: Fase W6
        onCtaTap: onIrAAlumnos,
      );
    }

    final title = switch (filtro) {
      NutricionFiltro.conPlan =>
        'Ningún alumno con plan todavía.', // i18n: Fase W6
      NutricionFiltro.sinPlan =>
        'Todos tus alumnos ya tienen plan.', // i18n: Fase W6
      // Inalcanzable en la práctica: "Todos" siempre incluye todo el
      // roster, así que si `hasAnyAlumno` es `true` este filtro nunca
      // produce una lista filtrada vacía. Mensaje defensivo por las dudas.
      NutricionFiltro.todos => 'Todavía no tenés alumnos.', // i18n: Fase W6
    };
    return TreinoEmptyState(
      key: ValueKey('nutricion_empty_${filtro.name}'),
      icon: TreinoIcon.emptyState,
      title: title,
    );
  }
}
