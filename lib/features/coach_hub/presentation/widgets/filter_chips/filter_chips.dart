import 'package:flutter/material.dart';

import '../../../../../app/theme/app_motion.dart';
import '../../../../../app/theme/tokens/components/treino_chip_tokens.dart';
import '../../../../../app/theme/tokens/components/treino_badge_tokens.dart';
import '../../../../../app/theme/tokens/components/treino_focus_tokens.dart';
import '../treino_interactive_state.dart';

/// FilterChips del kit Coach Hub Web — Fase 1.
///
/// Grupo de chips de filtro con soporte de:
/// - Single y multi-select.
/// - Estados: normal, selected, hover (web), disabled, focus (ring teclado)
///   — vía TreinoInteractiveState (fuente única de verdad, ADR-SH-002).
/// - Focusable y activable por teclado (Enter/Space), expone
///   Semantics(button: true) por chip.
/// - Badges numéricos opcionales por opción.
/// - Animación de selección via AppMotionTokens (micro/fast).
/// - Tokens: TreinoChipTokens.of(context) — nunca hex inline.
/// - Ambos temas dark y light.
///
/// Uso:
/// ```dart
/// TreinoFilterChips(
///   options: ['Activos', 'Inactivos'],
///   selected: {'Activos'},
///   onChanged: (newSet) => setState(() => _selected = newSet),
/// )
/// ```
class TreinoFilterChips extends StatelessWidget {
  const TreinoFilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.multiSelect = false,
    this.disabled = false,
    this.badgeCounts = const {},
  });

  /// Lista de opciones disponibles.
  final List<String> options;

  /// Conjunto de opciones actualmente seleccionadas.
  final Set<String> selected;

  /// Callback cuando cambia la selección.
  final void Function(Set<String> newSelected) onChanged;

  /// `true` = permite múltiples seleccionados. `false` = single select.
  final bool multiSelect;

  /// `true` = todos los chips deshabilitados (sin tap).
  final bool disabled;

  /// Mapa de conteos (badge) por opción. Ej: `{'Activos': 12}`.
  final Map<String, int> badgeCounts;

  void _handleTap(String option) {
    if (disabled) return;
    if (multiSelect) {
      final newSet = Set<String>.from(selected);
      if (newSet.contains(option)) {
        newSet.remove(option);
      } else {
        newSet.add(option);
      }
      onChanged(newSet);
    } else {
      // Single select: cambiar a la nueva opción
      if (selected.contains(option)) {
        onChanged({});
      } else {
        onChanged({option});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          _ChipItem(
            label: option,
            isSelected: selected.contains(option),
            isDisabled: disabled,
            badgeCount: badgeCounts[option],
            onTap: disabled ? null : () => _handleTap(option),
          ),
      ],
    );
  }
}

/// Chip individual — estado de interacción vía [TreinoInteractiveState]
/// (fuente única de verdad, ADR-SH-002): hover/focus/pressed + Semantics
/// + activación por teclado (Enter/Space).
class _ChipItem extends StatelessWidget {
  const _ChipItem({
    required this.label,
    required this.isSelected,
    required this.isDisabled,
    this.badgeCount,
    this.onTap,
  });

  final String label;
  final bool isSelected;
  final bool isDisabled;
  final int? badgeCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = TreinoChipTokens.of(context);
    final badgeTokens = TreinoBadgeTokens.of(context);
    final focusTokens = TreinoFocusTokens.of(context);

    return TreinoInteractiveState(
      onTap: onTap,
      builder: (ctx, states) {
        final disabled = states.disabled || isDisabled;

        // Resolver colores de fondo
        Color bg;
        if (disabled) {
          bg = tokens.defaultBackground;
        } else if (isSelected) {
          bg = tokens.selectedBackground;
        } else if (states.hovered) {
          bg = tokens.hoverBackground;
        } else {
          bg = tokens.defaultBackground;
        }

        // Resolver colores de texto
        Color fg;
        if (disabled) {
          fg = tokens.disabledForeground;
        } else if (isSelected) {
          fg = tokens.selectedForeground;
        } else {
          fg = tokens.defaultForeground;
        }

        // Border color (solo en selected)
        final borderColor =
            isSelected && !disabled ? tokens.selectedBorder : null;

        return AnimatedContainer(
          key: Key('filter_chip_$label'),
          duration: AppMotion.resolve(ctx, AppMotion.micro),
          curve: AppMotion.standard,
          decoration: BoxDecoration(
            color: bg,
            borderRadius:
                BorderRadius.circular(TreinoChipTokens.borderRadius),
            border: borderColor != null
                ? Border.all(color: borderColor)
                : Border.all(color: Colors.transparent),
            boxShadow: states.focused
                ? [
                    BoxShadow(
                      color: focusTokens.ring.withValues(alpha: 0.5),
                      spreadRadius: TreinoFocusTokens.ringWidth,
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Barlow',
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 14,
                  color: fg,
                ),
              ),
              if (badgeCount != null) ...[
                const SizedBox(width: 6),
                Container(
                  width: TreinoBadgeTokens.size,
                  height: TreinoBadgeTokens.size,
                  decoration: BoxDecoration(
                    color: badgeTokens.background,
                    borderRadius:
                        BorderRadius.circular(TreinoBadgeTokens.borderRadius),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    badgeCount!.toString(),
                    style: TextStyle(
                      fontFamily: 'Barlow',
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                      color: badgeTokens.foreground,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
