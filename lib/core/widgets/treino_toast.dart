import 'dart:async';

import 'package:flutter/material.dart';
import 'package:treino/app/theme/app_palette.dart';
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

/// Único punto de entrada para avisos efímeros de la app (#1560).
///
/// El estilo (flotante, radio, borde, margen sobre la nav) vive en
/// `AppTheme.snackBarTheme`; acá sólo se arma el contenido: ícono por tipo +
/// mensaje + acción opcional.
///
/// CASO SHEET/DIÁLOGO (#1490). Un `SnackBar` lo pinta el `Scaffold` registrado
/// en el `ScaffoldMessenger`, que es el de la pantalla de ATRÁS. Un
/// `showModalBottomSheet` o `showDialog` empuja una ruta encima del
/// `Scaffold`, así que el snackbar queda tapado y el usuario cree que el
/// botón no hace nada. Por eso, si `context` cuelga de una [PopupRoute], el
/// aviso va a una entrada del `Overlay` RAÍZ, que se dibuja por encima de
/// todas las rutas. Fuera de eso se usa el `ScaffoldMessenger` normal, que
/// respeta la nav flotante y el tema.
void showTreinoToast(
  BuildContext context,
  String message, {
  TreinoToastType type = TreinoToastType.info,
  TreinoToastAction? action,
}) {
  final enModal = ModalRoute.of(context) is PopupRoute;
  if (enModal) {
    _showEnOverlay(context, message, type, action);
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: _ToastContent(message: message, type: type),
        duration: _kToastDuration,
        // Explícito: con acción Material lo deja eterno por default
        // (ver snackbar_persist_scan_test).
        persist: false,
        action: action == null
            ? null
            : SnackBarAction(label: action.label, onPressed: action.onPressed),
      ),
    );
}

OverlayEntry? _entradaActual;
Timer? _timerActual;

void _cerrarOverlay() {
  _timerActual?.cancel();
  _timerActual = null;
  _entradaActual?.remove();
  _entradaActual?.dispose();
  _entradaActual = null;
}

void _showEnOverlay(
  BuildContext context,
  String message,
  TreinoToastType type,
  TreinoToastAction? action,
) {
  final overlay = Overlay.of(context, rootOverlay: true);
  _cerrarOverlay();
  final entrada = OverlayEntry(
    builder: (ctx) => Positioned(
      left: 20,
      right: 20,
      bottom: MediaQuery.viewPaddingOf(ctx).bottom + 20,
      child: _OverlayToast(
        message: message,
        type: type,
        action: action,
        onDismiss: _cerrarOverlay,
      ),
    ),
  );
  _entradaActual = entrada;
  overlay.insert(entrada);
  _timerActual = Timer(_kToastDuration, _cerrarOverlay);
}

class _OverlayToast extends StatelessWidget {
  const _OverlayToast({
    required this.message,
    required this.type,
    required this.action,
    required this.onDismiss,
  });

  final String message;
  final TreinoToastType type;
  final TreinoToastAction? action;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final snack = Theme.of(context).snackBarTheme;
    return Material(
      color: snack.backgroundColor ?? palette.bgCard,
      shape: snack.shape,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: DefaultTextStyle(
          style: snack.contentTextStyle ?? const TextStyle(),
          child: Row(
            children: [
              Expanded(child: _ToastContent(message: message, type: type)),
              if (action != null)
                TextButton(
                  onPressed: () {
                    onDismiss();
                    action!.onPressed();
                  },
                  child: Text(action!.label),
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
