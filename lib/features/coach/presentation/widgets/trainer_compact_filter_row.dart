import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_palette.dart';
import '../../application/trainer_discovery_providers.dart';
import '../../domain/discovery_filters.dart';
import 'trainer_advanced_filter_chips.dart'
    show
        TrainerFilterChip,
        showDistanceFilterSheet,
        showLocationRequiredFilterSheet,
        showPriceFilterSheet,
        showSpecialtyFilterSheet;
import 'trainer_specialty_chips.dart' show SpecialtyLabels;

/// Combined single-row chip strip used en modo MAPA.
///
/// Renderiza tres action chips dropdown idénticos en estilo, todos abren
/// un modal de selección al tap:
///   1. Distancia (depende de location permission)
///   2. Precio
///   3. Especialidad ("Todos" cuando null)
///
/// Reusa exactamente los mismos providers, modal sheets y estilos de chip
/// que [TrainerAdvancedFilterChips] + [TrainerSpecialtyChips] tienen en
/// modo LISTA — sin duplicar lógica de permisos ni de fetch de filtros.
class TrainerCompactFilterRow extends ConsumerWidget {
  const TrainerCompactFilterRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final distance = ref.watch(selectedDistanceFilterProvider);
    final price = ref.watch(selectedPriceFilterProvider);
    final specialty = ref.watch(selectedSpecialtyProvider);
    final locationAsync = ref.watch(athleteLocationProvider);
    final hasLocation = locationAsync.valueOrNull != null;
    final isLoadingLocation = locationAsync.isLoading;

    // Center el row cuando los 3 chips entran cómodos en el ancho de la
    // pantalla; cuando overflowea (phone chico o label largo tipo
    // "Buscando ubicación...") el SingleChildScrollView toma el ancho
    // completo y Center queda no-op — los chips arrancan en el padding
    // izquierdo y scrollean.
    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Distance ─────────────────────────────────────────────────
            TrainerFilterChip(
              label: isLoadingLocation && !hasLocation
                  ? 'Buscando ubicación...'
                  : distance.chipLabel,
              isActive: distance != DistanceFilter.any && hasLocation,
              disabled: !hasLocation && !isLoadingLocation,
              isLoading: isLoadingLocation && !hasLocation,
              palette: palette,
              onTap: () {
                if (isLoadingLocation && !hasLocation) return;
                if (hasLocation) {
                  showDistanceFilterSheet(context, ref, distance);
                } else {
                  showLocationRequiredFilterSheet(context, ref);
                }
              },
            ),
            const SizedBox(width: 8),
            // ── Price ────────────────────────────────────────────────────
            TrainerFilterChip(
              label: price.chipLabel,
              isActive: price != PriceFilter.any,
              disabled: false,
              isLoading: false,
              palette: palette,
              onTap: () => showPriceFilterSheet(context, ref, price),
            ),
            const SizedBox(width: 8),
            // ── Specialty (multi-select) ─────────────────────────────────
            TrainerFilterChip(
              label: specialty.isEmpty
                  ? 'Especialidad'
                  : specialty.length == 1
                      ? SpecialtyLabels.of(specialty.first)
                      : 'Especialidad · ${specialty.length}',
              isActive: specialty.isNotEmpty,
              disabled: false,
              isLoading: false,
              palette: palette,
              onTap: () => showSpecialtyFilterSheet(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}
