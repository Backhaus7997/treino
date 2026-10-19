import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/widgets/treino_icon.dart';

/// Tipo de aviso: define ícono y color (#1560).
enum TreinoToastType { success, error, info }

/// Acción opcional del toast ("DESHACER", "REINTENTAR"…).
class TreinoToastAction {
  const TreinoToastAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

const Duration _kToastDuration = Duration(seconds: 4);

/// Separación lateral del toast contra los bordes de la pantalla.
const double _kMargenLateral = AppSpacing.s20;

/// Ancho máximo del toast. En el teléfono no pesa (manda el margen lateral),
/// pero el Coach Hub es web: con sólo el margen, en un monitor de 1440 px el
/// aviso medía 1400 y se leía como una banda de borde a borde, el mismo
/// problema que este helper vino a sacar (#1560). Arriba del máximo el margen
/// crece y el toast queda centrado.
const double _kAnchoMaximo = 560;

/// Limita el toast a [_kAnchoMaximo] centrado, calculándolo en CADA layout.
///
/// Antes el margen lateral se calculaba una vez, al encolar el SnackBar, y
/// quedaba fijo: achicando la ventana del navegador con el toast a la vista,
/// los 440 px de cada lado de un monitor de 1440 quedaban aplicados a 600 y el
/// toast se quedaba sin ancho (Codex, #1593). Con un `LayoutBuilder` el ancho
/// sale del espacio real de ese frame, igual en el SnackBar y en el Overlay.
class _AnchoDelToast extends StatelessWidget {
  const _AnchoDelToast({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => Center(
          child: SizedBox(
            width: math.min(_kAnchoMaximo, box.maxWidth),
            child: child,
          ),
        ),
      );
}

/// Separación entre el toast y lo que tenga abajo: la barra de navegación,
/// el teclado o el borde seguro. Es un gap de diseño y NADA más: el
/// `Scaffold` ya ubica el SnackBar flotante arriba de `bottomNavigationBar`
/// (descuenta su alto aunque haya `extendBody`), así que sumar acá el alto
/// de la barra lo duplicaba y el aviso flotaba a ~80 px de la nav.
const double _kMargenInferior = AppSpacing.s12;

/// Estilo del toast del kit (#1560): flotante, con el radio y el borde de
/// una card.
///
/// Va EXPLÍCITO en cada SnackBar que arma el helper y no en
/// `ThemeData.snackBarTheme`, a propósito: el tema global restilizaría de
/// golpe los ~200 `SnackBar(` crudos todavía sin migrar —flotantes, con un
/// margen pensado para la nav en pantallas que no la tienen, como el Coach
/// Hub web o el player— sin QA de ninguna. Cada pantalla adopta el estilo
/// cuando migra a [showTreinoToast].
ShapeBorder _forma(AppPalette palette) => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      side: BorderSide(color: palette.border),
    );

TextStyle _estiloTexto(AppPalette palette) => GoogleFonts.barlow(
      color: palette.textPrimary,
      fontSize: AppTextSize.body,
      fontWeight: FontWeight.w600,
    );

/// Único punto de entrada para avisos efímeros de la app (#1560).
///
/// Arma el contenido (ícono por tipo + mensaje + acción opcional) y el estilo
/// del kit (ver [_forma]).
///
/// CASO SHEET/DIÁLOGO (#1490). Un `SnackBar` lo pinta el `Scaffold` registrado
/// en el `ScaffoldMessenger`, que es el de la pantalla de ATRÁS. Un
/// `showModalBottomSheet` o `showDialog` empuja una ruta encima del
/// `Scaffold`, así que el snackbar queda tapado y el usuario cree que el
/// botón no hace nada. Por eso, si `context` cuelga de una [PopupRoute], el
/// aviso va a una entrada del `Overlay` RAÍZ, que se dibuja por encima de
/// todas las rutas. Fuera de eso se usa el `ScaffoldMessenger` normal, que
/// respeta la nav flotante.
///
/// Una página `fullscreenDialog` NO cae en el caso Overlay: es una
/// `PageRoute` con su propio `Scaffold`, que se registra en el messenger y
/// pinta el SnackBar arriba de todo (lo fija un test).
///
/// Mostrar uno por cualquiera de los dos caminos cierra el que estuviera
/// visible por el otro: nunca hay dos avisos apilados.
///
/// [duration] es para los avisos con algo que decidir (un «Deshacer» que hay
/// que leer antes de tocar); el resto usa el default. [bottomOffset] despeja
/// contenido FIJO al pie que el `Scaffold` no conoce —un pie con «Guardar»
/// dentro del `body`—: la `bottomNavigationBar` ya la descuenta él solo.
void showTreinoToast(
  BuildContext context,
  String message, {
  TreinoToastType type = TreinoToastType.info,
  TreinoToastAction? action,
  Duration duration = _kToastDuration,
  double bottomOffset = 0,
}) {
  // Típico después de un `await`: la pantalla ya no está.
  if (!context.mounted) return;
  final enModal = ModalRoute.of(context) is PopupRoute;
  if (enModal) {
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    _showEnOverlay(context, message, type, action, duration, bottomOffset);
    return;
  }
  showTreinoToastOn(
    ScaffoldMessenger.of(context),
    message,
    type: type,
    action: action,
    duration: duration,
    bottomOffset: bottomOffset,
  );
}

/// Variante para código que ya capturó el messenger ANTES de un `await`
/// (el `context` puede estar desmontado al volver). No cubre el caso sheet:
/// ahí usá [showTreinoToast] con el context del sheet.
///
/// Por defecto el aviso nuevo REEMPLAZA al visible: es lo que se quiere en
/// una pantalla (el último resultado es el que importa). Con [encolar] el
/// aviso espera su turno detrás del visible, como hace el `ScaffoldMessenger`
/// de Material: lo usa el cartel de notificaciones de la web, que puede
/// recibir varios avisos seguidos y no debe perder ninguno (Codex, #1590).
void showTreinoToastOn(
  ScaffoldMessengerState messenger,
  String message, {
  TreinoToastType type = TreinoToastType.info,
  TreinoToastAction? action,
  Duration duration = _kToastDuration,
  double bottomOffset = 0,
  bool encolar = false,
}) {
  if (!messenger.mounted) return;
  if (!encolar) _cerrarOverlay();
  if (!encolar) messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      // El SnackBar es sólo el portador: transparente y sin padding, con
      // márgenes fijos. La tarjeta visible (fondo, borde, radio y acción)
      // va adentro, en [_AnchoDelToast], que recalcula el ancho en cada
      // frame.
      content: _AnchoDelToast(
        child: _ToastCard(
          message: message,
          type: type,
          action: action,
          onAction: messenger.hideCurrentSnackBar,
        ),
      ),
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(
        _kMargenLateral,
        0,
        _kMargenLateral,
        _kMargenInferior + bottomOffset,
      ),
      padding: EdgeInsets.zero,
      backgroundColor: Colors.transparent,
      elevation: 0,
      duration: duration,
      // La acción vive en la tarjeta, no en `SnackBar.action`: así el
      // SnackBar no la vuelve eterna y el toast se cierra solo igual
      // (ver snackbar_persist_scan_test).
      persist: false,
    ),
  );
}

/// Toast visible por Overlay, si lo hay. Su Timer NO vive acá sino en el
/// `State` de [_OverlayToast]: así se cancela solo si el Overlay se desmonta
/// (un Timer global sobrevivía al árbol y rompía widget tests ajenos con
/// `!timersPending`).
OverlayEntry? _entradaActual;

void _cerrarOverlay() {
  final entrada = _entradaActual;
  if (entrada == null) return;
  _entradaActual = null;
  // `remove()` va SIEMPRE, aunque la entrada ya no esté montada (el Overlay
  // se fue con el árbol): con el Overlay desmontado sale temprano sin tocar
  // nada, y es obligatorio antes de `dispose()`, que si no assertea.
  entrada
    ..remove()
    ..dispose();
}

void _showEnOverlay(
  BuildContext context,
  String message,
  TreinoToastType type,
  TreinoToastAction? action,
  Duration duration,
  double bottomOffset,
) {
  final overlay = Overlay.of(context, rootOverlay: true);
  _cerrarOverlay();
  late final OverlayEntry entrada;
  void cerrarEsta() {
    if (identical(_entradaActual, entrada)) _cerrarOverlay();
  }

  entrada = OverlayEntry(
    builder: (ctx) {
      return Positioned(
        left: _kMargenLateral,
        right: _kMargenLateral,
        // El mayor entre teclado y borde seguro: con el teclado abierto el
        // `viewPadding` sigue siendo el del home indicator y el toast quedaba
        // escondido debajo del teclado.
        bottom: math.max(
              MediaQuery.viewInsetsOf(ctx).bottom,
              MediaQuery.viewPaddingOf(ctx).bottom,
            ) +
            _kMargenInferior +
            bottomOffset,
        child: _AnchoDelToast(
          child: _OverlayToast(
            message: message,
            type: type,
            action: action,
            duration: duration,
            onDismiss: cerrarEsta,
          ),
        ),
      );
    },
  );
  _entradaActual = entrada;
  overlay.insert(entrada);
}

class _OverlayToast extends StatefulWidget {
  const _OverlayToast({
    required this.message,
    required this.type,
    required this.action,
    required this.duration,
    required this.onDismiss,
  });

  final String message;
  final TreinoToastType type;
  final TreinoToastAction? action;
  final Duration duration;
  final VoidCallback onDismiss;

  @override
  State<_OverlayToast> createState() => _OverlayToastState();
}

class _OverlayToastState extends State<_OverlayToast> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, widget.onDismiss);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Lo que el SnackBar de Material hace solo: sin `liveRegion` el lector de
    // pantalla no anuncia un aviso que aparece por Overlay.
    return Semantics(
      container: true,
      liveRegion: true,
      child: _ToastCard(
        message: widget.message,
        type: widget.type,
        action: widget.action,
        onAction: widget.onDismiss,
      ),
    );
  }
}

/// La tarjeta visible del toast, la misma por SnackBar y por Overlay: fondo
/// `bgCard`, borde y radio del kit, ícono por tipo, mensaje y acción opcional.
/// [onAction] cierra el toast antes de correr la acción.
class _ToastCard extends StatelessWidget {
  const _ToastCard({
    required this.message,
    required this.type,
    required this.action,
    required this.onAction,
  });

  final String message;
  final TreinoToastType type;
  final TreinoToastAction? action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final action = this.action;
    return Material(
      key: const Key('treino-toast-card'),
      color: palette.bgCard,
      shape: _forma(palette),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s14,
          vertical: AppSpacing.s12,
        ),
        child: DefaultTextStyle(
          style: _estiloTexto(palette),
          child: Row(
            children: [
              Expanded(child: _ToastContent(message: message, type: type)),
              if (action != null)
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: palette.accentText,
                  ),
                  onPressed: () {
                    onAction();
                    action.onPressed();
                  },
                  child: Text(action.label),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToastContent extends StatelessWidget {
  const _ToastContent({required this.message, required this.type});

  final String message;
  final TreinoToastType type;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final (icono, color) = switch (type) {
      TreinoToastType.success => (TreinoIcon.check, palette.accent),
      TreinoToastType.error => (TreinoIcon.errorState, palette.dangerText),
      TreinoToastType.info => (TreinoIcon.infoCircle, palette.textMuted),
    };
    return Row(
      children: [
        Icon(icono, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
      ],
    );
  }
}
