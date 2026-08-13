import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/widgets/motion/treino_tappable.dart';

/// Estado de interacción que un componente puede exponer a su builder.
///
/// Inmutable — se reconstruye en cada cambio de estado en [TreinoInteractiveState].
@immutable
class TreinoStates {
  const TreinoStates({
    this.hovered = false,
    this.pressed = false,
    this.focused = false,
    this.disabled = false,
  });

  /// El puntero del mouse está sobre el componente.
  final bool hovered;

  /// El componente está siendo presionado (tap down).
  final bool pressed;

  /// El componente tiene foco de teclado.
  final bool focused;

  /// onTap == null → sin interacción.
  final bool disabled;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TreinoStates &&
          runtimeType == other.runtimeType &&
          hovered == other.hovered &&
          pressed == other.pressed &&
          focused == other.focused &&
          disabled == other.disabled;

  @override
  int get hashCode => Object.hash(hovered, pressed, focused, disabled);
}

/// Resolver de estado de interacción unificado para el kit Coach Hub Web.
///
/// Combina [MouseRegion] + [FocusableActionDetector] + [TreinoTappable] en un
/// único widget que expone [TreinoStates] al [builder]. NO pinta nada por sí
/// mismo — delega completamente la visualización al builder.
///
/// Regla ADR-SH-002:
/// - onTap == null → disabled: sin gestos, sin hover, sin foco de teclado.
/// - Focus ring: responsabilidad del consumidor (usa TreinoFocusTokens.ring).
/// - Evita 7 copias de MouseRegion/FocusableActionDetector en los componentes.
///
/// Ejemplo de uso:
/// ```dart
/// TreinoInteractiveState(
///   onTap: onPressed,
///   builder: (ctx, states) => Container(
///     color: states.hovered ? tokens.hoverBackground : tokens.background,
///     child: Text(label),
///   ),
/// )
/// ```
class TreinoInteractiveState extends StatefulWidget {
  const TreinoInteractiveState({
    super.key,
    required this.builder,
    this.onTap,
    this.focusNode,
  });

  /// Si null → el componente está deshabilitado (sin gestos ni foco).
  final VoidCallback? onTap;

  /// Builder que recibe el [TreinoStates] actual y devuelve el widget a pintar.
  final Widget Function(BuildContext ctx, TreinoStates states) builder;

  /// FocusNode opcional para control externo del foco.
  final FocusNode? focusNode;

  @override
  State<TreinoInteractiveState> createState() => _TreinoInteractiveStateState();
}

class _TreinoInteractiveStateState extends State<TreinoInteractiveState> {
  bool _hovered = false;
  bool _focused = false;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(TreinoInteractiveState oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _focusNode.removeListener(_onFocusChange);
      if (oldWidget.focusNode == null) {
        // Eramos dueños del nodo anterior, lo disponemos.
        _focusNode.dispose();
      }
      _focusNode = widget.focusNode ?? FocusNode();
      _focusNode.addListener(_onFocusChange);
    }
    // Si onTap cambió a null, resetear estados interactivos.
    if (widget.onTap == null && (_hovered || _focused)) {
      setState(() {
        _hovered = false;
        _focused = false;
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) {
      // Solo disponemos si somos los dueños del nodo.
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _onFocusChange() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  void _onHoverChanged(bool value) {
    if (!mounted) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onTap == null;

    final states = TreinoStates(
      hovered: isDisabled ? false : _hovered,
      focused: isDisabled ? false : _focused,
      disabled: isDisabled,
    );

    final child = widget.builder(context, states);

    if (isDisabled) return child;

    // Mapa de acciones de teclado: Enter y Space activan onTap.
    final Map<Type, Action<Intent>> actions = {
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          widget.onTap?.call();
          return null;
        },
      ),
    };

    final Map<ShortcutActivator, Intent> shortcuts = {
      const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
      const SingleActivator(LogicalKeyboardKey.space): const ActivateIntent(),
    };

    return MouseRegion(
      onEnter: (_) => _onHoverChanged(true),
      onExit: (_) => _onHoverChanged(false),
      child: FocusableActionDetector(
        focusNode: _focusNode,
        actions: actions,
        shortcuts: shortcuts,
        child: TreinoTappable(
          onTap: widget.onTap,
          child: child,
        ),
      ),
    );
  }
}
