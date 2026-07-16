import 'package:flutter/material.dart';

import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/features/coach_hub/presentation/widgets/treino_interactive_state.dart';

/// Vista seleccionada del tab Mediciones — antropométricas o rendimiento.
enum MedicionView { antropometricas, rendimiento }

/// Toggle segmentado del tab Mediciones — Fase 3 WU-06a.
///
/// Extraído de `_MedicionesToggle` (`alumno_detail_screen.dart`,
/// ADR-A3-04). El kit v2 no tiene un segmented-toggle dedicado (los
/// candidatos son `TreinoFilterChips`, pensado para multi-opción con
/// badges, no para un selector binario tipo tab) — se mantiene bespoke pero
/// con motion vía `AppMotion` + `TreinoInteractiveState`, mismo patrón que
/// `TreinoFilterChips._ChipItem` (`filter_chips.dart`): el original era un
/// `InkWell` seco sin transición de color/borde.
class MedicionesToggle extends StatelessWidget {
  const MedicionesToggle({
    super.key,
    required this.view,
    required this.palette,
    required this.onChanged,
  });

  final MedicionView view;
  final AppPalette palette;
  final ValueChanged<MedicionView> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MedicionesToggleSegment(
            segmentKey: const Key('mediciones_toggle_antropometricas'),
            active: view == MedicionView.antropometricas,
            label: 'ANTROPOMÉTRICAS', // i18n: Fase W2
            palette: palette,
            onTap: () => onChanged(MedicionView.antropometricas),
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: _MedicionesToggleSegment(
            segmentKey: const Key('mediciones_toggle_rendimiento'),
            active: view == MedicionView.rendimiento,
            label: 'RENDIMIENTO', // i18n: Fase W2
            palette: palette,
            onTap: () => onChanged(MedicionView.rendimiento),
          ),
        ),
      ],
    );
  }
}

/// Segmento individual del toggle — estado de interacción vía
/// [TreinoInteractiveState] (fuente única de verdad, ADR-SH-002) +
/// [AnimatedContainer] para la transición de fondo/borde al activarse.
class _MedicionesToggleSegment extends StatelessWidget {
  const _MedicionesToggleSegment({
    required this.segmentKey,
    required this.active,
    required this.label,
    required this.palette,
    required this.onTap,
  });

  final Key segmentKey;
  final bool active;
  final String label;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TreinoInteractiveState(
      onTap: onTap,
      builder: (ctx, states) {
        return AnimatedContainer(
          key: segmentKey,
          duration: AppMotion.resolve(ctx, AppMotion.fast),
          curve: AppMotion.standard,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8 + 2),
          decoration: BoxDecoration(
            color: active ? palette.accent.withValues(alpha: 0.15) : null,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: active ? palette.accent : palette.border,
              width: active ? 1.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppFonts.barlowCondensed,
              color: active ? palette.accent : palette.textMuted,
              fontSize: 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: 0.4,
            ),
          ),
        );
      },
    );
  }
}
