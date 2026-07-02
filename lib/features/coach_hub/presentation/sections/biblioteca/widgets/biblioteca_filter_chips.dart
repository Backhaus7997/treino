// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../../app/theme/app_palette.dart';
import '../../../../../workout/domain/equipment_type.dart';
import '../../../../../workout/domain/muscle_group.dart';
import '../providers/biblioteca_providers.dart';

/// Inline filter chips for the Biblioteca Ejercicios tab.
///
/// Two [Wrap] rows:
/// 1. MÚSCULO — 12 [MuscleGroup.displayOrder] chips + "TODOS" (clear set).
/// 2. EQUIPAMIENTO — 13 [EquipmentType.values] chips + "TODOS" (clear set).
///
/// Chips toggle membership in [bibliotecaMuscleFilterProvider] /
/// [bibliotecaEquipmentFilterProvider] (OR within dimension, AND across).
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Muscle row ────────────────────────────────────────────────────
          _SectionLabel(label: 'MÚSCULO', palette: palette), // i18n
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TodosChip(
                active: selectedMuscles.isEmpty,
                palette: palette,
                onTap: () {
                  ref.read(bibliotecaMuscleFilterProvider.notifier).state =
                      const {};
                },
              ),
              for (final muscle in MuscleGroup.displayOrder)
                _FilterChip(
                  label: muscle.label.toUpperCase(), // i18n
                  active: selectedMuscles.contains(muscle),
                  palette: palette,
                  onTap: () {
                    final current = Set<MuscleGroup>.from(selectedMuscles);
                    if (current.contains(muscle)) {
                      current.remove(muscle);
                    } else {
                      current.add(muscle);
                    }
                    ref.read(bibliotecaMuscleFilterProvider.notifier).state =
                        current;
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          // ── Equipment row ─────────────────────────────────────────────────
          _SectionLabel(label: 'EQUIPAMIENTO', palette: palette), // i18n
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TodosChip(
                active: selectedEquipment.isEmpty,
                palette: palette,
                onTap: () {
                  ref.read(bibliotecaEquipmentFilterProvider.notifier).state =
                      const {};
                },
              ),
              for (final equip in EquipmentType.values)
                _FilterChip(
                  label: equip.label.toUpperCase(), // i18n
                  active: selectedEquipment.contains(equip),
                  palette: palette,
                  onTap: () {
                    final current = Set<EquipmentType>.from(selectedEquipment);
                    if (current.contains(equip)) {
                      current.remove(equip);
                    } else {
                      current.add(equip);
                    }
                    ref.read(bibliotecaEquipmentFilterProvider.notifier).state =
                        current;
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
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
      style: GoogleFonts.barlowCondensed(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: palette.textMuted,
        letterSpacing: 1.0,
      ),
    );
  }
}

/// "TODOS" chip — always-present, clears the filter set.
class _TodosChip extends StatelessWidget {
  const _TodosChip({
    required this.active,
    required this.palette,
    required this.onTap,
  });

  final bool active;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? palette.accent : palette.border,
            width: active ? 1.5 : 1,
          ),
          color:
              active ? palette.accent.withValues(alpha: 0.12) : palette.bgCard,
        ),
        child: Text(
          'TODOS', // i18n
          style: GoogleFonts.barlowCondensed(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? palette.accent : palette.textMuted,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

/// Individual filter chip — toggles in/out of the active filter set.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool active;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? palette.accent : palette.border,
            width: active ? 1.5 : 1,
          ),
          color:
              active ? palette.accent.withValues(alpha: 0.12) : palette.bgCard,
        ),
        child: Text(
          label,
          style: GoogleFonts.barlowCondensed(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? palette.accent : palette.textPrimary,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}
