import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/tokens/tokens.dart';
import '../../l10n/app_l10n.dart';

/// Barra "Listo" sobre el teclado numérico de iOS (#1500).
///
/// El teclado numérico de iOS (`number` / `phone`) no trae tecla de cierre ni
/// de acción: la única forma de bajarlo era tocar afuera. Hay ~17 campos
/// numéricos repartidos por la app, así que esto se monta UNA vez, en el
/// `builder` del `MaterialApp`, y mira el foco: cuando el campo enfocado es un
/// `EditableText` con teclado numérico y el teclado está arriba, aparece la
/// barra con "Listo", que le saca el foco. Ningún campo tiene que saber de
/// esto.
///
/// Sólo iOS: Android ya muestra la acción del teclado y en web no hay teclado
/// de software.
///
/// Mientras la barra está visible suma su altura a `viewInsets.bottom` del
/// subárbol, para que el `Scaffold` encoja y no tape el final del formulario.
class NumericKeyboardDoneBar extends StatefulWidget {
  const NumericKeyboardDoneBar({required this.child, super.key});

  final Widget child;

  /// Alto de la barra.
  static const double height = 44;

  @override
  State<NumericKeyboardDoneBar> createState() => _NumericKeyboardDoneBarState();
}

class _NumericKeyboardDoneBarState extends State<NumericKeyboardDoneBar> {
  bool _numericFocused = false;

  bool get _enabled => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_enabled) return;
    final next = _primaryFocusWantsNumericKeyboard();
    if (next == _numericFocused) return;
    // El foco puede cambiar en pleno build (autofocus): setState ahí tira.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _numericFocused = next);
      });
      return;
    }
    setState(() => _numericFocused = next);
  }

  bool _primaryFocusWantsNumericKeyboard() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null || !context.mounted) return false;
    final field = context.findAncestorWidgetOfExactType<EditableText>();
    if (field == null || field.readOnly) return false;
    // `TextInputType` compara por (index, signed, decimal): `number` no es
    // igual a `numberWithOptions(decimal: true)`. El índice es lo estable.
    final kind = field.keyboardType.index;
    return kind == TextInputType.number.index ||
        kind == TextInputType.phone.index;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final show = _enabled && _numericFocused && keyboard > 0;
    final extra = show ? NumericKeyboardDoneBar.height : 0.0;

    // La estructura es SIEMPRE la misma (Stack → MediaQuery → child): si el
    // child cambiara de posición en el árbol al aparecer la barra, el
    // Navigator se remontaría y se perdería toda la navegación.
    return Stack(
      children: [
        Positioned.fill(
          child: MediaQuery(
            data: media.copyWith(
              viewInsets: media.viewInsets.copyWith(bottom: keyboard + extra),
            ),
            child: widget.child,
          ),
        ),
        if (show)
          Positioned(
            left: 0,
            right: 0,
            bottom: keyboard,
            child: _DoneBar(
              onDone: () => FocusManager.instance.primaryFocus?.unfocus(),
            ),
          ),
      ],
    );
  }
}

class _DoneBar extends StatelessWidget {
  const _DoneBar({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: palette.bgCard,
      child: Container(
        height: NumericKeyboardDoneBar.height,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: palette.border)),
        ),
        child: TextButton(
          key: const Key('numeric_keyboard_done_button'),
          onPressed: onDone,
          child: Text(
            AppL10n.of(context).commonDone,
            style: TextStyle(
              color: palette.accentText,
              fontSize: AppTextSize.bodyLarge,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
