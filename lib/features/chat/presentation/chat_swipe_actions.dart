import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/semantics.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_motion.dart';
import '../../../app/theme/tokens/tokens.dart';

/// Una acción que el swipe deja a la vista detrás de la fila.
class ChatSwipeAction {
  const ChatSwipeAction({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;
}

/// Fila de la bandeja que se desliza hacia la izquierda y deja a la vista
/// [actions], como WhatsApp o Mail. Las acciones también se exponen como
/// acciones semánticas, así que un lector de pantalla no depende del gesto.
///
/// El movimiento sigue `apple-design`:
/// - 1:1 con el dedo, sin animar en el medio;
/// - al soltar decide con la velocidad PROYECTADA, no con la posición: un
///   flick corto abre aunque no haya llegado a la mitad;
/// - el resorte arranca desde donde está la fila y con la velocidad del dedo,
///   así que agarrarla en vuelo no salta;
/// - pasado un borde resiste (rubber band) en vez de frenar en seco;
/// - con «reducir movimiento» salta directo al estado final.
///
/// Sólo una fila abierta a la vez: todas comparten [openRow], y abrir una
/// cierra la anterior. Tocar una fila abierta la cierra en vez de abrir el
/// chat.
class ChatSwipeActions extends StatefulWidget {
  const ChatSwipeActions({
    super.key,
    required this.rowId,
    required this.openRow,
    required this.actions,
    required this.child,
    this.hint = false,
    this.onHintShown,
  });

  /// Identifica a esta fila dentro de [openRow].
  final Object rowId;

  /// Qué fila está abierta. Lo comparte toda la lista.
  final ValueNotifier<Object?> openRow;

  final List<ChatSwipeAction> actions;
  final Widget child;

  /// Asoma las acciones una vez, sola, para enseñar el gesto.
  final bool hint;

  /// Se llama cuando el asomo terminó, para no repetirlo.
  final VoidCallback? onHintShown;

  /// Ancho de cada acción revelada.
  static const double actionWidth = 80;

  /// Franja del borde izquierdo que NO arranca el swipe: es la del gesto de
  /// volver de iOS (20 px en `CupertinoPageRoute`) y del back predictivo de
  /// Android. Sin esto, deslizar desde el borde sobre una fila abriría la
  /// fila en vez de volver.
  static const double edgeExclusion = 24;

  @override
  State<ChatSwipeActions> createState() => _ChatSwipeActionsState();
}

class _ChatSwipeActionsState extends State<ChatSwipeActions>
    with SingleTickerProviderStateMixin {
  /// Desplazamiento de la fila en px: 0 cerrada, `-_extent` abierta.
  late final AnimationController _offset =
      AnimationController.unbounded(vsync: this);

  /// Posición del dedo sin la resistencia de los bordes. Se banda al pintar.
  double _drag = 0;

  double get _extent => ChatSwipeActions.actionWidth * widget.actions.length;
  bool get _isOpen => _offset.value < 0;

  @override
  void initState() {
    super.initState();
    widget.openRow.addListener(_onOpenRowChanged);
    if (widget.hint) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _playHint());
    }
  }

  @override
  void didUpdateWidget(ChatSwipeActions old) {
    super.didUpdateWidget(old);
    // Defensa: si esta fila pasa a ser OTRO chat, las acciones abiertas
    // serían del chat equivocado. Se cierra sin animar. No se toca
    // [openRow]: avisaría a las otras filas en medio de un build.
    if (old.rowId != widget.rowId) {
      _offset.stop();
      _offset.value = 0;
    }
    if (old.openRow != widget.openRow) {
      old.openRow.removeListener(_onOpenRowChanged);
      widget.openRow.addListener(_onOpenRowChanged);
    }
  }

  @override
  void dispose() {
    widget.openRow.removeListener(_onOpenRowChanged);
    if (widget.openRow.value == widget.rowId) widget.openRow.value = null;
    _offset.dispose();
    super.dispose();
  }

  void _onOpenRowChanged() {
    if (widget.openRow.value != widget.rowId && _offset.value != 0) {
      _settle(0);
    }
  }

  Future<void> _playHint() async {
    if (!mounted) return;
    // Con «reducir movimiento» no hay asomo: un desplazamiento solo, sin que
    // nadie lo pida, es justo lo que esa preferencia apaga.
    if (AppMotion.reduceMotion(context)) return;
    const peek = -ChatSwipeActions.actionWidth * 0.7;
    await Future<void>.delayed(AppMotion.slow);
    if (!mounted) return;
    await _offset.animateTo(
      peek,
      duration: AppMotion.slow,
      curve: AppMotion.emphasized,
    );
    if (!mounted) return;
    await Future<void>.delayed(AppMotion.slow);
    if (!mounted) return;
    await _offset.animateTo(
      0,
      duration: AppMotion.slow,
      curve: AppMotion.standard,
    );
    if (mounted) widget.onHintShown?.call();
  }

  void _onDragStart(DragStartDetails _) {
    // Interrumpible: arranca desde donde la fila está AHORA, aunque venga
    // animando.
    _offset.stop();
    _drag = _offset.value.clamp(-_extent, 0);
    widget.openRow.value = widget.rowId;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _drag += d.primaryDelta ?? 0;
    _offset.value = _banded(_drag);
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    // Proyección de momentum de UIKit (`decelerationRate` 0.99, la "rápida"):
    // a dónde iría la fila si la soltaran a esta velocidad.
    const rate = 0.99;
    final projected = _offset.value + velocity / 1000 * rate / (1 - rate);
    _settle(projected < -_extent / 2 ? -_extent : 0, velocity: velocity);
  }

  /// Resistencia progresiva fuera de `[-_extent, 0]`.
  double _banded(double x) {
    if (x > 0) return _rubberBand(x);
    if (x < -_extent) return -_extent - _rubberBand(-_extent - x);
    return x;
  }

  static double _rubberBand(double overshoot, [double dimension = 120]) {
    const c = 0.55;
    return overshoot * dimension * c / (dimension + c * overshoot.abs());
  }

  void _settle(double target, {double velocity = 0}) {
    if (target == 0 && widget.openRow.value == widget.rowId) {
      widget.openRow.value = null;
    }
    if (AppMotion.reduceMotion(context)) {
      _offset.value = target;
      return;
    }
    // Críticamente amortiguado (damping 1, response 0.3 s): se asienta sin
    // rebotar más allá del borde de las acciones.
    const response = 0.3;
    final spring = SpringDescription.withDampingRatio(
      mass: 1,
      stiffness: math.pow(2 * math.pi / response, 2).toDouble(),
      ratio: 1,
    );
    // El resorte termina DENTRO de su tolerancia, no en el destino exacto:
    // cerrado quedaría en -0,0005 y las acciones seguirían montadas en una
    // astilla invisible. Al completar se fija el valor justo.
    _offset
        .animateWith(SpringSimulation(spring, _offset.value, target, velocity))
        .then((_) {
      if (mounted) _offset.value = target;
    });
  }

  void _close() => _settle(0);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      customSemanticsActions: {
        for (final a in widget.actions)
          CustomSemanticsAction(label: a.label): a.onTap,
      },
      child: RawGestureDetector(
        gestures: {
          _EdgeAwareHorizontalDrag:
              GestureRecognizerFactoryWithHandlers<_EdgeAwareHorizontalDrag>(
            () => _EdgeAwareHorizontalDrag(isOpen: () => _isOpen),
            (r) => r
              ..onStart = _onDragStart
              ..onUpdate = _onDragUpdate
              ..onEnd = _onDragEnd,
          ),
        },
        child: AnimatedBuilder(
          animation: _offset,
          child: widget.child,
          builder: (context, child) {
            final revealed = math.max(0.0, -_offset.value);
            return Stack(
              children: [
                // Las acciones ocupan SÓLO lo revelado: la fila es
                // transparente sobre el fondo de la app, así que unas
                // acciones a ancho completo se verían a través de ella.
                if (revealed > 0)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    width: revealed,
                    child: Row(
                      children: [
                        for (final a in widget.actions)
                          Expanded(
                              child: _ActionButton(action: a, onDone: _close)),
                      ],
                    ),
                  ),
                Transform.translate(
                  offset: Offset(_offset.value, 0),
                  child: _isOpen
                      ? GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _close,
                          child: IgnorePointer(child: child),
                        )
                      : child,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action, required this.onDone});

  final ChatSwipeAction action;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: action.background,
      child: InkWell(
        onTap: () {
          onDone();
          action.onTap();
        },
        // Mientras se revela, el botón mide menos que su contenido: se
        // recorta en vez de desbordar.
        child: ClipRect(
          child: OverflowBox(
            minWidth: ChatSwipeActions.actionWidth,
            maxWidth: ChatSwipeActions.actionWidth,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(action.icon, color: action.foreground, size: 22),
                const SizedBox(height: AppSpacing.hairline),
                Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.barlow(
                    color: action.foreground,
                    fontSize: AppTextSize.caption,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Drag horizontal que no toma los toques que arrancan pegados al borde
/// izquierdo mientras la fila está cerrada: ese borde es del gesto de volver.
/// Ver [ChatSwipeActions.edgeExclusion].
class _EdgeAwareHorizontalDrag extends HorizontalDragGestureRecognizer {
  _EdgeAwareHorizontalDrag({required this.isOpen});

  final bool Function() isOpen;

  @override
  bool isPointerAllowed(PointerEvent event) {
    if (!isOpen() && event.position.dx < ChatSwipeActions.edgeExclusion) {
      return false;
    }
    return super.isPointerAllowed(event);
  }
}
