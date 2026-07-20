// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../app/theme/app_palette.dart';
import '../../../../../../app/theme/tokens/primitives.dart';
import '../../../../../workout/domain/equipment_type.dart';
import '../../../../../workout/domain/muscle_group.dart';
import '../../../widgets/coach_hub_widgets.dart';
import '../providers/biblioteca_providers.dart';

/// Etiqueta constante del chip que limpia el filtro de una dimensión.
const _kTodosLabel = 'TODOS'; // i18n

/// Inline filter chips for the Biblioteca Ejercicios tab.
///
/// Two rows built with [TreinoFilterChips] (kit — ADR-SH-002 interaction
/// states, animación de selección vía AppMotionTokens):
/// 1. MÚSCULO — 12 [MuscleGroup.displayOrder] chips + "TODOS" (clear set).
/// 2. EQUIPAMIENTO — 13 [EquipmentType.values] chips + "TODOS" (clear set).
///
/// [TreinoFilterChips] trabaja con `Set<String>` — este widget es el
/// adapter typed↔String que preserva la semántica de
/// [bibliotecaMuscleFilterProvider] / [bibliotecaEquipmentFilterProvider]
/// (OR dentro de la dimensión, AND entre dimensiones).
///
/// ADR-CHW-005: NO bottom sheet. Inline chips only.
/// REQ-BIBW-06, SCENARIO-BIBW-06a, SCENARIO-BIBW-06b, SCENARIO-BIBW-06c,
/// SCENARIO-BIBW-06d.
class BibliotecaFilterChips extends ConsumerWidget {
  const BibliotecaFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final selectedMuscles = ref.watch(bibliotecaMuscleFilterProvider);
    final selectedEquipment = ref.watch(bibliotecaEquipmentFilterProvider);

    final muscleOptions = [
      _kTodosLabel,
      ...MuscleGroup.displayOrder.map((m) => m.label.toUpperCase()),
    ];
    final selectedMuscleLabels = selectedMuscles.isEmpty
        ? {_kTodosLabel}
        : selectedMuscles.map((m) => m.label.toUpperCase()).toSet();

    final equipmentOptions = [
      _kTodosLabel,
      ...EquipmentType.values.map((e) => e.label.toUpperCase()),
    ];
    final selectedEquipmentLabels = selectedEquipment.isEmpty
        ? {_kTodosLabel}
        : selectedEquipment.map((e) => e.label.toUpperCase()).toSet();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Muscle row ────────────────────────────────────────────────────
          _SectionLabel(label: 'MÚSCULO', palette: palette), // i18n
          const SizedBox(height: AppSpacing.hairline),
          TreinoFilterChips(
            options: muscleOptions,
            selected: selectedMuscleLabels,
            multiSelect: true,
            onChanged: (newSelected) {
              ref.read(bibliotecaMuscleFilterProvider.notifier).state =
                  _resolveMuscleSelection(
                previousSelected: selectedMuscleLabels,
                newSelected: newSelected,
              );
            },
          ),
          const SizedBox(height: AppSpacing.s12),
          // ── Equipment row ─────────────────────────────────────────────────
          _SectionLabel(label: 'EQUIPAMIENTO', palette: palette), // i18n
          const SizedBox(height: AppSpacing.hairline),
          TreinoFilterChips(
            options: equipmentOptions,
            selected: selectedEquipmentLabels,
            multiSelect: true,
            onChanged: (newSelected) {
              ref.read(bibliotecaEquipmentFilterProvider.notifier).state =
                  _resolveEquipmentSelection(
                previousSelected: selectedEquipmentLabels,
                newSelected: newSelected,
              );
            },
          ),
          const SizedBox(height: AppSpacing.s12),
        ],
      ),
    );
  }

  /// Resuelve el nuevo `Set<MuscleGroup>` a escribir en el provider a partir
  /// del `Set<String>` que devuelve [TreinoFilterChips].
  ///
  /// Regla de desambiguación de "TODOS": si el usuario tocó el chip TODOS
  /// (pasa a estar seleccionado y antes no lo estaba), se limpia el filtro.
  /// En cualquier otro caso, se mapean las etiquetas != TODOS de vuelta a
  /// [MuscleGroup] (por [MuscleGroup.label] en mayúsculas).
  static Set<MuscleGroup> _resolveMuscleSelection({
    required Set<String> previousSelected,
    required Set<String> newSelected,
  }) {
    if (newSelected.contains(_kTodosLabel) &&
        !previousSelected.contains(_kTodosLabel)) {
      return const {};
    }
    final resolved = <MuscleGroup>{};
    for (final label in newSelected) {
      if (label == _kTodosLabel) continue;
      for (final muscle in MuscleGroup.displayOrder) {
        if (muscle.label.toUpperCase() == label) {
          resolved.add(muscle);
          break;
        }
      }
    }
    return resolved;
  }

  /// Análogo a [_resolveMuscleSelection] para [EquipmentType].
  static Set<EquipmentType> _resolveEquipmentSelection({
    required Set<String> previousSelected,
    required Set<String> newSelected,
  }) {
    if (newSelected.contains(_kTodosLabel) &&
        !previousSelected.contains(_kTodosLabel)) {
      return const {};
    }
    final resolved = <EquipmentType>{};
    for (final label in newSelected) {
      if (label == _kTodosLabel) continue;
      for (final equipment in EquipmentType.values) {
        if (equipment.label.toUpperCase() == label) {
          resolved.add(equipment);
          break;
        }
      }
    }
    return resolved;
  }
}

// ── Private sub-widgets ───────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.palette});
  final String label;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontFamily: AppFonts.barlowCondensed,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: palette.textMuted,
        letterSpacing: 1.0,
      ),
    );
  }
}
