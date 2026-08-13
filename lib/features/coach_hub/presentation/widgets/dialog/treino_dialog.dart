import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../../app/theme/tokens/components/treino_dialog_tokens.dart';
import '../../../../../app/theme/tokens/components/treino_focus_tokens.dart';
import '../../../../../app/theme/tokens/motion_tokens.dart';
import '../../../../../app/theme/tokens/primitives.dart';
import '../../../../../core/widgets/treino_icon.dart';
import '../preview_wrapper.dart';
import '../treino_interactive_state.dart';

/// Previews del kit — Finding W3.
@Preview(name: 'Dialog — normal', wrapper: coachHubPreviewWrapper)
Widget treinoDialogPreview() => TreinoDialog(
      title: 'Confirmar baja',
      body: const Text('¿Seguro que querés dar de baja al alumno?'),
      primaryLabel: 'Confirmar',
      secondaryLabel: 'Cancelar',
      onPrimaryTap: () {},
      onSecondaryTap: () {},
    );

@Preview(name: 'Dialog — destructive', wrapper: coachHubPreviewWrapper)
Widget treinoDialogDestructivePreview() => TreinoDialog(
      title: 'Eliminar alumno',
      body: const Text('Esta acción no se puede deshacer.'),
      primaryLabel: 'Eliminar',
      secondaryLabel: 'Cancelar',
      destructive: true,
      onPrimaryTap: () {},
      onSecondaryTap: () {},
    );

/// Abre un [TreinoDialog] (o cualquier widget) con la anatomía y motion del
/// kit Coach Hub Web — Fase 1.
///
/// Entrada/salida: fade + scale (`0.95 → 1.0`) con [AppMotionTokens.enter] y
/// duración [AppMotionTokens.contentEnter]. Respeta `reduceMotion`
/// (`transitionDuration = Duration.zero`).
///
/// Uso:
/// ```dart
/// showTreinoDialog<bool>(
///   context,
///   builder: (ctx) => TreinoDialog(
///     title: 'Confirmar baja',
///     body: const Text('¿Seguro que querés dar de baja al alumno?'),
///     primaryLabel: 'Confirmar',
///     destructive: true,
///     onPrimaryTap: () => Navigator.of(ctx).pop(true),
///   ),
/// );
/// ```
Future<T?> showTreinoDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final tokens = TreinoDialogTokens.of(context);
  final reduceMotion = AppMotionTokens.reduceMotion(context);

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: tokens.overlayColor,
    transitionDuration:
        reduceMotion ? Duration.zero : AppMotionTokens.contentEnter,
    pageBuilder: (dialogContext, animation, secondaryAnimation) =>
        builder(dialogContext),
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotionTokens.enter,
        reverseCurve: AppMotionTokens.leave,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Dialog base del kit Coach Hub Web — Fase 1.
///
/// Anatomía: header (título + botón cerrar), body (contenido + error inline
/// opcional), actions (secundario + primario).
///
/// Estados:
/// - Normal.
/// - Destructive: CTA primario en [TreinoDialogTokens.destructiveColor].
/// - Loading: spinner en el botón primario, deshabilitado.
/// - Error inline: mensaje en el body.
///
/// Foco: autofocus al abrir + Escape cierra el dialog (si `barrierDismissible`
/// del [showTreinoDialog] que lo abrió lo permite vía `Navigator.pop`).
///
/// Tokens: [TreinoDialogTokens.of(context)] — nunca hex inline.
class TreinoDialog extends StatelessWidget {
  const TreinoDialog({
    super.key,
    required this.title,
    this.body,
    this.primaryLabel,
    this.onPrimaryTap,
    this.secondaryLabel,
    this.onSecondaryTap,
    this.destructive = false,
    this.loading = false,
    this.errorMessage,
  });

  /// Título del header.
  final String title;

  /// Contenido del body. Null = sin body adicional.
  final Widget? body;

  /// Texto del botón de acción primaria (ej: "Confirmar").
  final String? primaryLabel;

  /// Callback del botón primario. Ignorado mientras [loading] es `true`.
  final VoidCallback? onPrimaryTap;

  /// Texto del botón de acción secundaria (ej: "Cancelar").
  final String? secondaryLabel;

  /// Callback del botón secundario.
  final VoidCallback? onSecondaryTap;

  /// `true` = el botón primario usa el color destructivo (danger).
  final bool destructive;

  /// `true` = spinner en el botón primario, sin interacción.
  final bool loading;

  /// Mensaje de error inline, mostrado debajo del body. Null = sin error.
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final tokens = TreinoDialogTokens.of(context);
    final palette = AppPalette.of(context);

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              Navigator.of(context).maybePop();
              return null;
            },
          ),
        },
        child: FocusScope(
          autofocus: true,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: TreinoDialogTokens.maxWidth,
              ),
              child: Material(
                color: tokens.background,
                borderRadius:
                    BorderRadius.circular(TreinoDialogTokens.borderRadius),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.s20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(title: title, tokens: tokens),
                      if (body != null) ...[
                        const SizedBox(height: AppSpacing.s12),
                        body!,
                      ],
                      if (errorMessage != null) ...[
                        const SizedBox(height: AppSpacing.s12),
                        Text(
                          errorMessage!,
                          style: TextStyle(
                            fontFamily: AppFonts.barlow,
                            fontSize: 13,
                            color: palette.danger,
                          ),
                        ),
                      ],
                      if (primaryLabel != null || secondaryLabel != null) ...[
                        const SizedBox(height: AppSpacing.s20),
                        _Actions(
                          primaryLabel: primaryLabel,
                          onPrimaryTap: onPrimaryTap,
                          secondaryLabel: secondaryLabel,
                          onSecondaryTap: onSecondaryTap,
                          destructive: destructive,
                          loading: loading,
                          tokens: tokens,
                          palette: palette,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Header del dialog: título + botón cerrar.
class _Header extends StatelessWidget {
  const _Header({required this.title, required this.tokens});

  final String title;
  final TreinoDialogTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontFamily: AppFonts.barlowCondensed,
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: tokens.titleColor,
            ),
          ),
        ),
        IconButton(
          key: const Key('dialog_close_button'),
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(TreinoIcon.close, color: tokens.contentColor, size: 18),
          splashRadius: 18,
        ),
      ],
    );
  }
}

/// Fila de acciones del dialog: secundario + primario.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.primaryLabel,
    required this.onPrimaryTap,
    required this.secondaryLabel,
    required this.onSecondaryTap,
    required this.destructive,
    required this.loading,
    required this.tokens,
    required this.palette,
  });

  final String? primaryLabel;
  final VoidCallback? onPrimaryTap;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryTap;
  final bool destructive;
  final bool loading;
  final TreinoDialogTokens tokens;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final primaryColor = destructive ? tokens.destructiveColor : palette.accent;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (secondaryLabel != null)
          _DialogActionButton(
            actionKey: const Key('dialog_secondary_button'),
            onTap: onSecondaryTap,
            color: tokens.contentColor,
            label: secondaryLabel!,
          ),
        if (primaryLabel != null) ...[
          const SizedBox(width: AppSpacing.s8),
          _DialogActionButton(
            actionKey: const Key('dialog_primary_button'),
            onTap: loading ? null : onPrimaryTap,
            color: primaryColor,
            label: primaryLabel!,
            loading: loading,
          ),
        ],
      ],
    );
  }
}

/// Botón de acción del [TreinoDialog] (primario/secundario).
///
/// Estado de interacción vía [TreinoInteractiveState] (fuente única de
/// verdad, ADR-SH-002): focusable, activable por teclado (Enter/Space),
/// expone Semantics(button: true) y resalta fondo en hover/pressed + anillo
/// de foco en focus. Con [loading]=true muestra un spinner en vez del label
/// y queda deshabilitado (sin gesto ni foco), delegando al `onTap: null` de
/// [TreinoInteractiveState].
class _DialogActionButton extends StatelessWidget {
  const _DialogActionButton({
    required this.actionKey,
    required this.onTap,
    required this.color,
    required this.label,
    this.loading = false,
  });

  final Key actionKey;
  final VoidCallback? onTap;
  final Color color;
  final String label;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final focusTokens = TreinoFocusTokens.of(context);

    return TreinoInteractiveState(
      onTap: onTap,
      builder: (ctx, states) {
        final highlighted = states.hovered || states.pressed;

        return Container(
          key: actionKey,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s8,
            vertical: AppSpacing.s8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: highlighted ? color.withValues(alpha: 0.08) : null,
            border: states.focused ? Border.all(color: focusTokens.ring) : null,
          ),
          child: loading
              ? SizedBox(
                  key: const Key('dialog_primary_spinner'),
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontFamily: AppFonts.barlow,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: color,
                  ),
                ),
        );
      },
    );
  }
}
