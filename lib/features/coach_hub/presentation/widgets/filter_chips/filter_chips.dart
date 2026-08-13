import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../app/theme/app_motion.dart';
import '../../../../../app/theme/tokens/components/treino_chip_tokens.dart';
import '../../../../../app/theme/tokens/components/treino_badge_tokens.dart';
import '../../../../../app/theme/tokens/components/treino_focus_tokens.dart';

/// FilterChips del kit Coach Hub Web — Fase 1.
///
/// Grupo de chips de filtro con soporte de:
/// - Single y multi-select.
/// - Estados: normal, selected, hover (web), disabled, focus (ring teclado).
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

/// Chip individual con estado hover, focus y animación.
class _ChipItem extends StatefulWidget {
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
  State<_ChipItem> createState() => _ChipItemState();
}

class _ChipItemState extends State<_ChipItem> {
  bool _hovered = false;
  final _focusNode = FocusNode();

  // Mapa de acciones de teclado
  late final Map<Type, Action<Intent>> _actions = {
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) {
        widget.onTap?.call();
        return null;
      },
    ),
  };

  static const _shortcuts = {
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  };

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = TreinoChipTokens.of(context);
    final badgeTokens = TreinoBadgeTokens.of(context);
    final focusTokens = TreinoFocusTokens.of(context);

    final isDisabled = widget.isDisabled || widget.onTap == null;

    // Resolver colores de fondo
    Color bg;
    if (isDisabled) {
      bg = tokens.defaultBackground;
    } else if (widget.isSelected) {
      bg = tokens.selectedBackground;
    } else if (_hovered) {
      bg = tokens.hoverBackground;
    } else {
      bg = tokens.defaultBackground;
    }

    // Resolver colores de texto
    Color fg;
    if (isDisabled) {
      fg = tokens.disabledForeground;
    } else if (widget.isSelected) {
      fg = tokens.selectedForeground;
    } else {
      fg = tokens.defaultForeground;
    }

    // Border color (solo en selected)
    final borderColor =
        widget.isSelected && !isDisabled ? tokens.selectedBorder : null;

    final chip = AnimatedContainer(
      duration: AppMotion.resolve(context, AppMotion.micro),
      curve: AppMotion.standard,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(TreinoChipTokens.borderRadius),
        border: borderColor != null
            ? Border.all(color: borderColor)
            : Border.all(color: Colors.transparent),
        boxShadow: _focusNode.hasFocus && !isDisabled
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
            widget.label,
            style: TextStyle(
              fontFamily: 'Barlow',
              fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w400,
              fontSize: 14,
              color: fg,
            ),
          ),
          if (widget.badgeCount != null) ...[
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
                widget.badgeCount!.toString(),
                style: const TextStyle(
                  fontFamily: 'Barlow',
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (isDisabled) return chip;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: FocusableActionDetector(
        focusNode: _focusNode,
        actions: _actions,
        shortcuts: _shortcuts,
        onFocusChange: (_) => setState(() {}),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: chip,
        ),
      ),
    );
  }
}
